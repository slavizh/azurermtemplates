param
(
      [string]$IPaddresses = $null,
      [string]$clusterName = $null,
	  [string]$elasticSearchSource = $null,
	  [string]$jdkSource = $null
)

try {

	#formatting data disk
	Write-Host "Initializing and formatting data disk" -ForegroundColor green
	
    $disks = Get-Disk | Where partitionstyle -eq 'raw' | sort number

	$driveLetter = "F"
	if($disks -ne $null)
	{
		$disks[0] | Initialize-Disk -PartitionStyle MBR -PassThru |	New-Partition -UseMaximumSize -DriveLetter $driveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel "data1" -Confirm:$false -Force 
	}
	#with reference from: http://belczyk.com/2014/07/elasticsearch-one-click-installation-script-for-windows/

	#download java from a location you choose to temporary drive
	$jdkDestination = "D:\jdk-installer.exe"

	Invoke-WebRequest $jdkSource -OutFile $jdkDestination

	#install java
	$jdkInstallLocation = "C:\Program Files\JAVA\JDK"
	Start-Process -FilePath $jdkDestination -ArgumentList "/s INSTALLDIR=`"$jdkInstallLocation`"" -PassThru -Wait

	# download elasticsearch to temporary drive
	$destination = "D:\elasticsearch.zip"
 
	Invoke-WebRequest $elasticSearchSource -OutFile $destination

	#unzip files
	$shell = new-object -com shell.application
	$zip = $shell.NameSpace($destination)
	$unzipDest = $shell.Namespace("$driveLetter`:\")

	$elasticSearchPath = '$driveLetter:\elasticsearch'

	foreach($item in $zip.items())
	{
		$unzipDest.copyhere($item)
		$elasticSearchPath = Join-path $unzipDest.Self.Path -ChildPath $item.name
	}

	$jdkPath = $jdkInstallLocation	

	$elasticSearchBinPath = join-path $elasticSearchPath '\bin'
	$configPath = join-path $elasticSearchPath  '\config\elasticsearch.yml'

	$esAreadyInstalled = $FALSE		
	$configOK = $true
		
	# Validate the configuration
	write-host "Validating config" -foregroundcolor green

	if (-not (test-path $elasticSearchBinPath))
	{
		write-host "ElasticSearch bin path doesn't exist: $elasticSearchBinPath" -foregroundcolor red
		return;	
	}

	if (-not (test-path $jdkPath))
	{
		write-host "Java JDK path doesn't exist: $jdkPath"  -foregroundcolor red
		return;
	}
		
	# Setting JAVA_HOME	
	write-host "setting JAVA_HOME system variable" -foregroundcolor green

	if ([environment]::GetEnvironmentVariable("JAVA_HOME", "machine") -eq $null)
	{
		[environment]::setenvironmentvariable("JAVA_HOME", $jdkpath, "machine")
		$env:JAVA_HOME = $jdkpath
	}

	write-host "JAVA_HOME system variable set to: " $jdkpath -foregroundcolor gray

	# Set cluster name
	Write-Host "Setting cluster name" -foregroundcolor green 
		
	if($clusterName -eq $null)
	{
		$clusterName = "elasticsearch"
	}

	(Get-Content $configPath) | ForEach-Object { $_ -replace "#?\s?cluster.name: .+" , "cluster.name: $clusterName" } | Set-Content $configPath
	Write-Host "Cluster name is: $clusterName" -foregroundcolor gray	

	# Set discovery
	Write-Host "Changing discovery settings" -foregroundcolor green 
		
	(Get-Content $configPath) | ForEach-Object { $_ -replace "#?\s?discovery.zen.ping.multicast.enabled: false+" , "discovery.zen.ping.multicast.enabled: false" } | Set-Content $configPath
	Write-Host "Enabled unicast" -foregroundcolor gray

	(Get-Content $configPath) | ForEach-Object { $_ -replace '#?\s?discovery.zen.ping.unicast.hosts: .+' , "discovery.zen.ping.unicast.hosts: [$IPaddresses]" } | Set-Content $configPath
	Write-Host "added ip addresses of nodes" -foregroundcolor gray			 

	#Install ElasticSearch as a service
	Write-Host "Install ElasticSearch as a service" -foregroundcolor green 

	cd $elasticSearchBinPath 

	if (-not (Get-Service "elasticsearch-service-x64" -ErrorAction SilentlyContinue) )
	{
		.\service.bat install
		Write-Host "ElasticSearch installed." -foregroundcolor gray
	}
	else
	{
		Write-Host "ElasticSearch have been already installed." -foregroundcolor gray
		$esAreadyInstalled = $TRUE
	}

	# Install HEAD plugin	
	Write-Host "Install HEAD plugin" -foregroundcolor green 

	cd $elasticSearchBinPath 

	.\plugin.bat -install mobz/elasticsearch-head

	Write-Host "HEAD plugin installed." -foregroundcolor gray
		 
	# Start ElasticSearch service	
	Write-Host "Start ElasticSearch service" -foregroundcolor green

	Start-Service 'elasticsearch-service-x64'

	Write-Host "Set service startup type to automatic" -foregroundcolor green 

	Set-Service 'elasticsearch-service-x64' -StartupType automatic

	# Enable ports through firewall 
	New-NetFirewallRule -DisplayName "Allow Port 9200 in" -Direction Inbound -LocalPort 9200 -Protocol TCP -Action Allow
	New-NetFirewallRule -DisplayName "Allow Port 9200 out" -Direction Outbound -LocalPort 9200 -Protocol TCP -Action Allow
	New-NetFirewallRule -DisplayName "Allow Port 9300 in" -Direction Inbound -LocalPort 9300 -Protocol TCP -Action Allow
	New-NetFirewallRule -DisplayName "Allow Port 9300 out" -Direction Outbound -LocalPort 9300 -Protocol TCP -Action Allow

	Write-Host "ElasticSearch endpoint: http://localhost:9200" -foregroundcolor green 

	Write-Host "Completed with success" -foregroundcolor green 

}
finally{
	Write-Host "End"
}