#TODO: Add Reading passwords from file (need to sleep between users to prevent locks and script malfunction)

#----Internal Section DONOT Change---

$Domain = ((cmd /c set u)[-3] -split "=")[-1] #Get domain name

$PDC = ((nltest.exe /dcname:$Domain) -split "\\\\")[1] #Get The PDC Emulator Role Holder Bad password Count to prevent locks

$lockoutBadPwdCount = ((net accounts /domain)[7] -split ":" -replace " ", "")[1] #Get password policy to prevent locks of the users

#---Changes Bellow this line is allowed----

$GroupToCheck = "GroupName" #Defined All if needed to get all the domain users or any other group

if (Test-Path '.\userslist.txt') { $UsersToCheck = Get-Content '.\userslist.txt' } #if exist users file import and ignore group else get all group members

else {

    if ($GroupToCheck.ToLower() -eq "all") {

        $UsersToCheck = (Get-ADUser -SearchBase $(Get-ADDomain).DistinguishedName -Filter * -Properties Enabled | Where-Object { $_.Enabled }).SamAccountName #get all enabled users in the domain bypass limits on the results

    }

    else {

        $UsersToCheck = (Get-ADGroupMember -Recursive $GroupToCheck).SamAccountName | ForEach-Object { (Get-ADUser -Properties Enabled -Identity $_).Samaccountname } #get all enabled users within specific group.

    }

}

$password = "Aa123456" #defined the one password that you want to check

$UsersWithPassFile = 'c:\temp\UsersFound.txt' #set the location and the file name of the results file

$noPassInFile = $false #flag to control if password is needed in the log file, set to $false if no password is needed

$privGroups = @("Domain Admins", "Account Operators") #Groups to set High Privilege flag to add groups

 

if (Test-Path $UsersWithPassFile) {

    Remove-Item $UsersWithPassFile -Force #delete the old file to prevent old tarce

}

 

$privGroupsMem = $privGroups | ForEach-Object { (Get-ADGroupMember -Recursive $_ -ea SilentlyContinue ).SamAccountName } #Get all users in privilege

 

$UsersToCheck | ForEach-Object {

    #line bellow is to get the badpassword count and password last set time and date

    $badPwdCount = Get-ADObject -SearchBase $((Get-ADUser $_).DistinguishedName) -Filter * -Properties badpwdcount, pwdLastSet -Server $PDC | Select-Object DistinguishedName, Name, @{N = 'PasswordDate'; Exp = { [datetime]::FromFileTime($_.pwdLastSet).ToString('dd-MM-yyyy hh:mm:ss') } }, badpwdcount

    if ($badPwdCount.badpwdcount -lt $lockoutBadPwdCount - 3) {

        #this line to prevent locks in the domain

        $DoaminAdminLoc = "{0},{1}" -f "CN=Domain Admins", $(Get-ADDomain).UsersContainer #get the 'domain admins' group DN for checking for working creds

        $UserUPN = "{0}@{1}" -f $_, $(Get-ADDomain).DNSRoot #get the user UPN for authenticate to AD with the $password

        $isInvalid = dsacls.exe $DoaminAdminLoc /user:$UserUPN /passwd:$password /simple | select-string -pattern "Invalid Credentials" #try connect to AD with the user (UPN) and $password in simple LDAP bind, and looking for "Invalid Credentials", if $null the User and the password are correct

        if ($isInvalid -match "Invalid") {

            Write-Host "[-] Invalid Credentials for $_ : $password : PasswordCount: "$badPwdCount.badpwdcount -foreground red #write to screen if the credentials are invalid and the bad password count for controlling and debugging

        }

        else {

            Write-Host "[+] Working Credentials for $_ : $password PasswordLastSet: " $badPwdCount.PasswordDate "High Privilege User: "($privGroupsMem.contains($_)) -foreground green #write to screen if the password has been worked and the password last set date

            if ($noPassInFile) {

                $finding = "User: {0} With Password {1} PasswordLastSet: {2} High Privilege User: {3}" -f $_, $password, $badPwdCount.PasswordDate,($privGroupsMem.contains($_)) #create format to write to the file

            }

            else {

                $finding = "User: {0} With Password {1} PasswordLastSet: {2} High Privilege User: {3}" -f $_, "******", $badPwdCount.PasswordDate, ($privGroupsMem.contains($_)) #create format to write to the file

            }

            Write-Output $finding | Tee-Object $UsersWithPassFile -Append | Out-Null #write to file all good credentials to $UsersWithPassFile file

        }        

    }

}
