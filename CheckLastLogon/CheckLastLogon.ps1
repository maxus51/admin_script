#@maxus51
param (
    [string]$GroupName
)

# Проверяем, что имя группы передано
if (-not $GroupName) {
    Write-Error "Параметр GroupName обязателен. Используйте -GroupName 'имя_группы'."
    exit
}

# Импортируем модуль Active Directory
Import-Module ActiveDirectory

# Получаем список пользователей из группы
$users = Get-ADGroupMember -Identity $GroupName | Where-Object { $_.objectClass -eq 'user' }

# Создаем пустой массив для хранения результатов
$results = @()

# Проходим по каждому пользователю и получаем время последнего входа, статус блокировки, состояние учетной записи, срок действия и отдел
foreach ($user in $users) {
    $adUser = Get-ADUser -Identity $user.SamAccountName -Properties LastLogon, LockoutTime, UserAccountControl, AccountExpirationDate, Department
    $lastLogon = $adUser.LastLogon
    $lockoutTime = $adUser.LockoutTime
    $userAccountControl = $adUser.UserAccountControl
    $accountExpirationDate = $adUser.AccountExpirationDate
    $department = $adUser.Department

    if ($lastLogon) {
        $lastLogonDate = [datetime]::FromFileTime($lastLogon)
    } else {
        $lastLogonDate = "Never logged on"
    }

    # Проверяем, заблокирована ли учетная запись
    $isLockedOut = $lockoutTime -gt 0

    # Проверяем, отключена ли учетная запись
    $isDisabled = ($userAccountControl -band 0x0002) -ne 0

    # Определяем статус учетной записи
    $accountStatus = switch ($true) {
        $isLockedOut { "Locked Out" }
        $isDisabled { "Disabled" }
        default { "Active" }
    }

    # Добавляем результаты в массив
    $results += [PSCustomObject]@{
        UserName = $user.SamAccountName
        LastLogon = $lastLogonDate
        AccountStatus = $accountStatus
        AccountExpirationDate = if ($accountExpirationDate) { $accountExpirationDate.ToString("yyyy-MM-dd") } else { "Never expires" }
        Department = if ($department) { $department } else { "Not specified" }
    }
}

# Выводим результаты, сортируя по LastLogon в порядке убывания
$results | Sort-Object @{Expression={if($_.LastLogon -eq "Never logged on") {[datetime]::MinValue} else {$_.LastLogon}}} -Descending | Format-Table -AutoSize
