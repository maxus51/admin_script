# Импортируем модуль Active Directory
Import-Module ActiveDirectory

# Запрашиваем у пользователя логин
$login = Read-Host "Введите логин для поиска"

# Получаем список доменов из леса Active Directory
try {
    $forestDomains = (Get-ADForest).Domains
} catch {
    Write-Host "Ошибка: Не удалось получить список доменов леса." -ForegroundColor Red
    exit
}

# Получаем список доверенных доменов (Outbound или Bidirectional)
try {
    $trustedDomains = Get-ADTrust -Filter "*" | Where-Object { $_.Direction -eq "Outbound" -or $_.Direction -eq "Bidirectional" } | Select-Object -ExpandProperty Target
} catch {
    Write-Host "Ошибка: Не удалось получить список доверенных доменов." -ForegroundColor Red
    exit
}

# Объединяем списки доменов и сортируем их
$allDomains = ($forestDomains + $trustedDomains) | Sort-Object -Unique

# Массив для хранения результатов
$results = @()

# Функция для поиска пользователя в домене
function Find-UserInDomain {
    param (
        [string]$domain,
        [string]$userLogin
    )
    try {
        # Пытаемся найти пользователя в домене
        $user = Get-ADUser -Filter { SamAccountName -eq $userLogin } -Server $domain -ErrorAction Stop
        if ($user) {
            return $domain
        }
    } catch {
        # Если пользователь не найден или произошла ошибка, возвращаем $null
        return $null
    }
}

# Проходим по всем доменам и ищем пользователя
foreach ($domain in $allDomains) {
    Write-Host "Поиск в домене: $domain"
    $foundDomain = Find-UserInDomain -domain $domain -userLogin $login
    if ($foundDomain) {
        $results += $foundDomain
    }
}

# Выводим результаты
if ($results.Count -gt 0) {
    Write-Host "Пользователь '$login' найден в следующих доменах:" -ForegroundColor Green
    foreach ($domain in $results) {
        Write-Host "- $domain"
    }
} else {
    Write-Host "Пользователь '$login' не найден ни в одном из доменов." -ForegroundColor Yellow
}
