# Путь к локальному файлу
$localFilePath = "C:\script\cer\localhos.pem"

# Данные для подключения к удаленному серверу
$sshServer = "172.16.40.1"
$sshUser = "admsrv"
$sshPass = "******" # Замените на реальный пароль
$remoteFilePath = "/etc/ssl/localhost/localhost.pem"

# Путь к OpenSSL
$opensslPath = "C:\Program Files\OpenSSL-Win64\bin\openssl.exe"

# Пароль для PFX-файла
$pfxPassword = "12345678"

# Формат имени PFX-файла
$pfxFileNameFormat = "certificate_{0}.pfx" # {0} заменяется на текущую дату
$pfxFileDirectory = "C:\script\cer"

# Установка модуля Posh-SSH (если он еще не установлен)
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Установка модуля Posh-SSH..."
    Install-Module -Name Posh-SSH -Scope CurrentUser -Force
}

# Импорт модуля Posh-SSH
Import-Module Posh-SSH

# Создание объекта SecureString для пароля
$securePassword = ConvertTo-SecureString $sshPass -AsPlainText -Force

# Создание учетных данных для SSH
$credential = New-Object System.Management.Automation.PSCredential ($sshUser, $securePassword)

# Функция для скачивания текстового файла через SSH
function Download-TextFile {
    param (
        [string]$localPath,
        [string]$remotePath
    )
    try {
        Write-Host "Скачивание текстового файла с удаленного сервера..."
        $command = "cat $remotePath"
        $result = Invoke-SSHCommand -Index 0 -Command $command

        if ($result.ExitStatus -ne 0) {
            Write-Host "Ошибка при чтении удаленного файла: $($result.Error)"
            return
        }

        # Сохранение содержимого файла в локальный файл
        Set-Content -Path $localPath -Value $result.Output
        Write-Host "Файл успешно скачан: $localPath"
    }
    catch {
        Write-Host "Произошла ошибка при скачивании файла: $_"
    }
}

# Подключение к серверу по SSH
try {
    $session = New-SSHSession -ComputerName $sshServer -Credential $credential -AcceptKey:$true
    if (-not $session.Connected) {
        Write-Host "Не удалось подключиться к серверу: $sshServer"
        exit
    }

    # Флаг для определения необходимости конвертации
    $shouldConvert = $false

    # Проверка существования локального файла
    if (-not (Test-Path $localFilePath)) {
        Write-Host "Локальный файл не существует. Скачиваем файл с удаленного сервера..."
        Download-TextFile -localPath $localFilePath -remotePath $remoteFilePath
        $shouldConvert = $true
    }
    else {
        # Получение даты последнего изменения локального файла
        $localFileDate = (Get-Item $localFilePath).LastWriteTime

        # Команда для получения даты последнего изменения удаленного файла
        $remoteCommand = "stat -c %Y $remoteFilePath"
        $remoteFileDateUnix = Invoke-SSHCommand -Index 0 -Command $remoteCommand | Select-Object -ExpandProperty Output

        # Преобразование Unix-времени в DateTime
        $remoteFileDate = [datetime]::Parse("1970-01-01").AddSeconds($remoteFileDateUnix)

        # Сравнение дат
        if ($remoteFileDate -gt $localFileDate) {
            Write-Host "Удаленный файл новее локального. Начинаем скачивание..."
            Download-TextFile -localPath $localFilePath -remotePath $remoteFilePath
            $shouldConvert = $true
        }
        else {
            Write-Host "Локальный файл актуален. Обновление не требуется."
        }
    }

    # Конвертация PEM в PFX, если файл был обновлен
    if ($shouldConvert) {
        # Генерация имени файла PFX с текущей датой
        $currentDate = Get-Date -Format "yyyyMMdd" # Формат: ГГГГММДД
        $pfxFileName = $pfxFileNameFormat -f $currentDate
        $pfxFilePath = Join-Path -Path $pfxFileDirectory -ChildPath $pfxFileName

        if (-not (Test-Path $opensslPath)) {
            Write-Host "OpenSSL не найден по пути: $opensslPath"
            exit
        }

        Write-Host "Конвертация PEM в PFX..."

        $arguments = @(
            "pkcs12",
            "-export",
            "-out", "`"$pfxFilePath`"",
            "-in", "`"$localFilePath`"",
            "-passout", "pass:$pfxPassword",
            "-keypbe", "PBE-SHA1-3DES", # Явное указание алгоритма шифрования
            "-certpbe", "PBE-SHA1-3DES" # Явное указание алгоритма шифрования
        )

        Start-Process -FilePath $opensslPath -ArgumentList $arguments -NoNewWindow -Wait

        if (Test-Path $pfxFilePath) {
            Write-Host "Файл успешно конвертирован: $pfxFilePath"

            # Чтение данных из PFX
            try {
                Write-Host "Чтение данных из PFX-файла..."
    
                $certPassword = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    
                # Вариант 1: Попробуем без пароля (если PFX не защищён)
                try {
                    $cert.Import($pfxFilePath)
                }
                catch {
                    # Вариант 2: Пробуем с паролем
                    $cert.Import($pfxFilePath, $certPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
                }

                if (-not $cert.Thumbprint) {
                    throw "Не удалось загрузить сертификат. Возможно, неверный пароль или повреждённый файл."
                }

                Write-Host "Отпечаток (Thumbprint): $($cert.Thumbprint)"
                Write-Host "Истекает: $($cert.NotAfter)"
                Write-Host "Subject: $($cert.Subject)"

                # Установка сертификата в LocalMachine\My
                Write-Host "Установка сертификата в LocalMachine\My..."
                $localMachineStore = New-Object System.Security.Cryptography.X509Certificates.X509Store "My", "LocalMachine"
                $localMachineStore.Open("ReadWrite")
                $localMachineStore.Add($cert)
                $localMachineStore.Close()
                Write-Host "Сертификат установлен в LocalMachine\My."

                # Обновление SSL-сертификата ADFS
                if (Get-Command -Name Set-AdfsSslCertificate -ErrorAction SilentlyContinue) {
                    Write-Host "Обновление SSL-сертификата ADFS..."
                    Set-AdfsSslCertificate -Thumbprint $cert.Thumbprint
                    Write-Host "SSL-сертификат ADFS успешно обновлён!"
                }
                else {
                    Write-Warning "Модуль ADFS не найден. Команда Set-AdfsSslCertificate недоступна."
                }

                # Обновление сертификата для взаимодействия служб ADFS
                if (Get-Command -Name Set-AdfsCertificate -ErrorAction SilentlyContinue) {
                    Write-Host "Обновление сертификата для взаимодействия служб ADFS..."
                    Set-AdfsCertificate -CertificateType "Service-Communications" -Thumbprint $cert.Thumbprint
                    Write-Host "Сертификат служб ADFS успешно обновлён!"
                }
                else {
                    Write-Warning "Модуль ADFS не найден. Команда Set-AdfsCertificate недоступна."
                }

                # Перезапуск службы ADFS
                try {
                    Write-Host "Перезапуск службы ADFS..."
                    Restart-Service adfssrv -Force -ErrorAction Stop
                    Write-Host "Служба ADFS перезапущена!"
                }
                catch {
                    Write-Warning "Не удалось перезапустить службу ADFS: $_"
                }
            }
            catch {
                Write-Host "Ошибка при чтении PFX: $_"
                Write-Host "Попробуйте открыть файл вручную через certmgr.msc."
            }
        }
        else {
            Write-Host "Ошибка при конвертации файла."
        }
    }
}
catch {
    Write-Host "Произошла ошибка: $_"
}
finally {
    # Закрытие SSH-сессии
    if ($session -and $session.Connected) {
        Remove-SSHSession -Index 0 | Out-Null
    }
}
