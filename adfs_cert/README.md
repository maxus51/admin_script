# Автоматизация обновления SSL-сертификата ADFS

Этот скрипт автоматизирует процесс обновления SSL-сертификата для службы ADFS (Active Directory Federation Services). Он выполняет следующие шаги:
1. Проверяет наличие локального PEM-файла и скачивает его с удалённого сервера, если он отсутствует или устарел.
2. Конвертирует PEM-файл в PFX-формат с использованием OpenSSL.
3. Извлекает данные из PFX-файла (отпечаток, срок действия, доменное имя).
4. Устанавливает сертификат в хранилище `LocalMachine\My`.
5. Обновляет SSL-сертификат ADFS и сертификат для взаимодействия служб ADFS.
6. Перезапускает службу ADFS для применения изменений.

## Требования

1. **Модуль PowerShell**:
   - Модуль `Posh-SSH` для работы с SSH.
   - Командлеты ADFS (`Set-AdfsSslCertificate`, `Set-AdfsCertificate`) для обновления сертификатов.

2. **Программное обеспечение**:
   - Установленный OpenSSL (`C:\Program Files\OpenSSL-Win64\bin\openssl.exe`).

3. **Права доступа**:
   - Скрипт должен выполняться с правами администратора для установки сертификата и перезапуска службы ADFS.

## Настройка

1. Заполните переменные в начале скрипта:
   ```powershell
   $localFilePath = "C:\script\cer\localhost.pem"
   $sshServer = "172.16.40.1"
   $sshUser = "admsrv"
   $sshPass = "******" # Замените на реальный пароль
   $remoteFilePath = "/etc/ssl/localhost/localhost.pem"
   $opensslPath = "C:\Program Files\OpenSSL-Win64\bin\openssl.exe"
   $pfxPassword = "12345678"
