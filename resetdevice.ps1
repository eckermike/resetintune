[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Mandatory = $False)] [bool]$deleteonly
)

begin {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    if($env:USERDOMAIN -notlike $env:COMPUTERNAME){
        Write-host "Please run this script with a local account with administrative rights."
        pause
        exit 1
    }
    Start-Transcript .\intunereset.log -Force 
    try {
        #make sure nuget package providor is installed
        $nuget = Get-PackageProvider -Name nuget
        if (!($nuget)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force }

        #make sure powershellget is isntalled
        $psget = Get-Module powershellget
        if (!($psget)) { install-module -Name powershellget -Force }
 
        #make sure psgallery is installed and trusted
        $psgallery = Get-PSRepository -Name PSGallery 
        if (!($psgallery)) { $psgallery = Register-PSRepsitory -Default -InstallationPolicy Trusted }
        if ($psgallery.InstallationPolicy -ne "Trusted") { Set-PSRepository -Name PSgallery -InstallationPolicy Trusted }
 
        #isntall required modules
        Install-Module -Name azuread -AllowClobber  | Out-Null
        Import-Module azuread
        Install-Module -Name Microsoft.graph.intune -AllowClobber  | Out-Null
        import-module microsoft.graph.intune
        Install-Module -Name WindowsAutoPilotIntune -AllowClobber  | Out-Null
        Import-Module windowsautopilotintune
        Install-Script -Name get-windowsautopilotinfo -Force  -NoPathUpdate | Out-Null
    }
    catch {
        write-host "Error adding necessary modules. Please make sure you are running with local administrative rights."
        stop-transcript
        exit 1
    }
 
    try {
        #pull intune id and serial number into variables
        $IntuneCertificate = Get-ChildItem -Path Cert:\LocalMachine -Recurse | Where-Object { $_.Issuer -Like "*Microsoft Intune MDM Device CA*"}
        $id = $IntuneCertificate.Subject.Split('=')[1]
        $serial = (Get-CimInstance -ClassName win32_bios).SerialNumber
    }
    catch {
        write-host "Error pulling require info on local device.  Possible the device is not joined to intune."
        stop-transcript
        exit 1
    }
    #connect to the online services
    Connect-MSGraph -ForceInteractive
    Connect-AzureAD
 
    try {
        #remove device from intune
        $Intunedevice = Get-DeviceManagement_ManagedDevices -managedDeviceId $id
        if ($Intunedevice) {
            Remove-DeviceManagement_ManagedDevices -managedDeviceId $id | Out-Null
        }
    }
    catch{
            Write-Host "issue removeing device from intune"
        }
     try {
        $aaddevice = Get-AzureADDevice -SearchString $Intunedevice.deviceName
        if($aaddevice){
            if($aaddevice.count){
                $aaddevice | %{Remove-AzureADDevice -ObjectId $_.objectid}
            }else{
                Remove-AzureADDevice -ObjectId $aaddevice.objectid
            }
        }
    }
    catch {
        write-host "Error while removeing device from AAD."
    }
    try { 
        $APDevice = Get-AutopilotDevice -serial (Get-CimInstance win32_bios).SerialNumber
        if ($ApDevice) { Remove-AutopilotDevice -id $APDevice.id | Out-Null }
    }
    catch {
        write-host "Error removing device from autopilot."
    }

    if ($deleteonly) {
        write-host "Skipping rejoin"
        Stop-Transcript
        exit 0
    }
    else {
        #run command to add device to autopilot
        & "$env:ProgramFiles\WindowsPowerShell\Scripts\Get-WindowsAutoPilotInfo.ps1" -online -addtogroup Deskside_Autopilot
        Stop-Transcript
        exit 0
    }
    write-host "Something unexpected happened"
    stop-transcript
    exit 1
}
