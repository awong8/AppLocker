﻿#test
Function Merge-AppLockerPolicyXml
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [String]
        $SourceFile,

        [Parameter(Mandatory)]
        [ValidateScript({$_ | Test-Path})]
        [String[]]
        $AppendFile,

        [Parameter(Mandatory)]
        [String]
        $OutputFile
    )
    
    Begin
    {
        [xml]$SourceFile = Get-Content $SourceFile
    }
    Process
    {
        Foreach ($Append in $AppendFile)
        {
            [xml]$Append = Get-Content $Append
            $Type = ($Append.ChildNodes.ChildNodes).Type
            $Rule = $SourceFile.ChildNodes.SelectNodes("RuleCollection[@Type=`'$Type`']")
            ForEach ($XmlNode in $Append.DocumentElement.ChildNodes.ChildNodes)
            {    
                $Rule.PrependChild($SourceFile.ImportNode($XmlNode, $true)) | Out-Null
            }
            $SourceFile.Save("$OutputFile")
        }
    }
}

Function Get-AppLockerEvent 
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [switch]
        $SinceLastApply   
    )
    
    Begin {
        
    }
    
    Process
    {
        $LogName = 'Microsoft-Windows-AppLocker/EXE and DLL'
        $Properties = @{LogName = $LogName
                        Id = '8001'}
        If ($SinceLastApply.IsPresent)
        {
            Try
            {
            $StartTime = Get-WinEvent -FilterHashtable $Properties -MaxEvents 1 -ErrorAction Stop | Select-Object -Expand TimeCreated
            $Properties["Id"] = '8003','8004'
            $Properties["StartTime"] = $StartTime
            }
            Catch
            {
            Write-Error "Unable to retrieve last policy applied date. Log entry may have been over written or do not exist."
            }   
        }
        Else
        {
            $Properties["Id"] = '8003','8004'
        }
        Try
        {
            Get-WinEvent -FilterHashtable $Properties -ErrorAction Stop
        }
        Catch { Write-Output "No matching event found."}
    }
    
    End {
        
    }
}

function New-AppLockerBaseLinePolicy {
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $OutputFile = "$Env:HOMEDRIVE\Support\$($Env:COMPUTERNAME)_AppLocker_Baseline.xml",

        [Parameter()]
        [switch]
        $SetLocalPolicy
    )
    
    Begin {
        [System.Collections.ArrayList]$allPrograms = @()
        If (-not(Test-Path $Env:HOMEDRIVE\Support)) { New-Item -Name Support -Type Directory -Path $Env:HOMEDRIVE\ | Out-Null }      
    }
    
    Process {
        $xml = New-Object -TypeName XML
        $xmlRoot = $xml.CreateElement("AppLockerPolicy")
        $xmlRoot.SetAttribute("Version","1")
        $xml.AppendChild($xmlRoot) | Out-Null

        $nodes = @("Appx","Dll","Exe","Msi","Script")
        $nodes | ForEach-Object {
            $ruleCollect = $xml.CreateElement("RuleCollection")
            $ruleCollect.SetAttribute("Type","$_")
            $ruleCollect.SetAttribute("EnforcementMode","AuditOnly")
            $xml.AppLockerPolicy.AppendChild($ruleCollect) | Out-Null
        }

        $nodes | Where-Object { $_ -notmatch "Appx" -and $_ -notmatch "Exe" -and $_ -notmatch "Dll" } | ForEach-Object {
            $filePathRule = $xml.AppLockerPolicy.SelectSingleNode("RuleCollection[@Type=`'$_`']")
            $guid = (New-Guid).Guid
            $filePathRuleElm = $xml.CreateNode("element","FilePathRule","")
            $filePathRuleElm.SetAttribute("Id","$guid")
            $filePathRuleElm.SetAttribute("Name","(Default Rule) All $_`'s")
            $filePathRuleElm.SetAttribute("Description","")
            $filePathRuleElm.SetAttribute("UserOrGroupSid","S-1-1-0")
            $filePathRuleElm.SetAttribute("Action","Allow")
            $filePathRule.AppendChild($filePathRuleElm) | Out-Null

            $con = $xml.SelectSingleNode("//*[@Id=`'$guid`']")
            $conElm = $xml.CreateNode("element","Conditions","")
            $con.AppendChild($conElm) | Out-Null

            $filePathCon = $xml.SelectSingleNode("//*[@Id=`'$guid`']").SelectSingleNode("Conditions")
            $filePathConElm = $xml.CreateElement("FilePathCondition")
            $filePathConElm.SetAttribute("Path","*")
            $filePathCon.AppendChild($filePathConElm) | Out-Null
        }

        $filePathRule = $xml.AppLockerPolicy.SelectSingleNode("RuleCollection[@Type='Appx']")
        $guid = (New-Guid).Guid
        $filePathRuleElm = $xml.CreateNode("element","FilePublisherRule","")
        $filePathRuleElm.SetAttribute("Id","$guid")
        $filePathRuleElm.SetAttribute("Name","(Default Rule) All signed packaged apps")
        $filePathRuleElm.SetAttribute("Description","Allows members of the Everyone group to run packaged apps that are signed.")
        $filePathRuleElm.SetAttribute("UserOrGroupSid","S-1-1-0")
        $filePathRuleElm.SetAttribute("Action","Allow")
        $filePathRule.AppendChild($filePathRuleElm) | Out-Null

        $con = $xml.SelectSingleNode("//*/FilePublisherRule")
        $conElm = $xml.CreateNode("element","Conditions","")
        $con.AppendChild($conElm) | Out-Null

        $con = $xml.SelectSingleNode("//*/FilePublisherRule").SelectSingleNode("Conditions")
        $conElm = $xml.CreateNode("element","FilePublisherCondition","")
        $conElm.SetAttribute("BinaryName","*")
        $conElm.SetAttribute("ProductName","*")
        $conElm.SetAttribute("PublisherName","*")
        $con.AppendChild($conElm) | Out-Null

        $thresExt = $xml.SelectSingleNode("//*/FilePublisherCondition")
        $servicesElm = $xml.CreateNode("element","BinaryVersionRange","")
        $servicesElm.SetAttribute("LowSection","0.0.0.0")
        $servicesElm.SetAttribute("HighSection","*")
        $thresExt.AppendChild($servicesElm) | Out-Null

        $filePathRule = $xml.AppLockerPolicy.SelectSingleNode("RuleCollection[@Type='Exe']")
        $guid = (New-Guid).Guid

        $filePathRuleElm = $xml.CreateNode("element","FilePathRule","")
        $filePathRuleElm.SetAttribute("Id","$guid")
        $filePathRuleElm.SetAttribute("Name","(Default Rule) Allow everyone to execute all files located in the Windows folder")
        $filePathRuleElm.SetAttribute("Description","")
        $filePathRuleElm.SetAttribute("UserOrGroupSid","S-1-1-0")
        $filePathRuleElm.SetAttribute("Action","Allow")
        $filePathRule.AppendChild($filePathRuleElm) | Out-Null

        $con = $xml.SelectSingleNode("//*[@Id=`'$guid`']")
        $conElm = $xml.CreateNode("element","Conditions","")
        $con.AppendChild($conElm) | Out-Null

        $con = $xml.SelectSingleNode("//*[@Id=`'$guid`']")
        $conElm = $xml.CreateNode("element","Exceptions","")
        $con.AppendChild($conElm) | Out-Null

        $exception = $xml.SelectSingleNode("//*[@Id=`'$guid`']").SelectSingleNode("Exceptions")
        $exceptItems = @(   '%SYSTEM32%\catroot2\*',
                            '%SYSTEM32%\com\dmp\*',
                            '%SYSTEM32%\Debug\*',
                            '%SYSTEM32%\FxsTmp\*',
                            '%SYSTEM32%\spool\drivers\color\*',
                            '%SYSTEM32%\spool\PRINTERS\*',
                            '%SYSTEM32%\spool\SERVERS\*',
                            '%SYSTEM32%\Tasks\*',
                            '%WINDIR%\PCHEALTH\ERRORREP\*',
                            '%WINDIR%\Registration\*',
                            '%WINDIR%\SysWOW64\com\dmp\',
                            '%WINDIR%\SysWOW64\FxsTmp\*',
                            '%WINDIR%\SysWOW64\Tasks\*',
                            '%WINDIR%\Tasks\*',
                            '%WINDIR%\Temp\*',
                            '%WINDIR%\tracing\*')
        Foreach ($exceptItem in $exceptItems) {
            $filePathConElm = $xml.CreateElement("FilePathCondition")
            $filePathConElm.SetAttribute("Path","$exceptItem")
            $exception.AppendChild($filePathConElm) | Out-Null    
        }
        $filePathCon = $xml.SelectSingleNode("//*[@Id=`'$guid`']").SelectSingleNode("Conditions")
        $filePathConElm = $xml.CreateElement("FilePathCondition")
        $filePathConElm.SetAttribute("Path","%WINDIR%\*")
        $filePathCon.AppendChild($filePathConElm) | Out-Null

        Get-ChildItem ${Env:ProgramFiles(x86)} | Select-Object -Expand FullName | ForEach-Object {
            $testPath = Get-ChildItem $_ -Filter *.exe -Recurse -ErrorAction SilentlyContinue
            If ($testPath.Count -eq 1) { $allPrograms += $testPath.DirectoryName.Replace("C:\Program Files (x86)","%PROGRAMFILES%") + "\*" }
            If ($testPath.Count -gt 1) { $allPrograms += $_.Replace("C:\Program Files (x86)","%PROGRAMFILES%") + "\*" }
        }

        Get-ChildItem $Env:ProgramFiles | Select-Object -Expand FullName | ForEach-Object {
            $testPath = Get-ChildItem $_ -Filter *.exe -Recurse -ErrorAction SilentlyContinue
            If ($testPath.Count -eq 1) { $allPrograms += $testPath.DirectoryName.Replace("C:\Program Files","%PROGRAMFILES%") + "\*" }
            If ($testPath.Count -gt 1) { $allPrograms += $_.Replace("C:\Program Files","%PROGRAMFILES%") + "\*" }
        }

        @('%PROGRAMFILES%\Windows Media Player\*',
        '%PROGRAMFILES%\Windows Photo Viewer\*',
        '%PROGRAMFILES%\Windows Mail\*'
        ) | ForEach-Object { while ($allPrograms -contains $_) {$allPrograms.Remove($_)} }

        $allPrograms = $allPrograms | Where-Object { $_ -notlike "*windows nt*"}
        
        Get-ChildItem $Env:ALLUSERSPROFILE | Select-Object -Expand FullName | ForEach-Object {
            $testPath = Get-ChildItem $_ -Filter *.exe -Recurse -ErrorAction SilentlyContinue
            If ($testPath.Count -eq 1) { $allPrograms += $testPath.DirectoryName.Replace("C:\ProgramData)","%OSDRIVE%\PROGRAMDATA") + "\*" }
            If ($testPath.Count -gt 1) { $allPrograms += $_.Replace("C:\ProgramData","%OSDRIVE%\PROGRAMDATA") + "\*" }
        }

        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }
        $roots = $drives | Where-Object { $_.Description -ne "Temporary Storage" -and $_.Name -ne "Temp" } | Select-Object -ExpandProperty Root
        If ($roots)
        {
            Foreach ($root in $roots)
            { 
                $dirs = Get-ChildItem $root -Directory | Where-Object { $_.Name -ne "Program Files" -and $_.Name -ne "Windows" -and $_.Name -ne "Program Files (x86)" -and $_.Name -ne "Users"} | Select-Object -ExpandProperty FullName | Sort
                Foreach ($dir in $dirs)
                {
                    $dirName = Get-ChildItem $dir -Recurse -Filter *.exe -ErrorAction SilentlyContinue -verbose | Select-Object DirectoryName | Select-Object -ExpandProperty DirectoryName
                    if ($dirName.Count -gt 0 -and $((Get-ChildItem $dir -Depth 0 -Filter *.exe).Count) -eq 0) { $allPrograms += $dir + "\*" }
                    elseif ($dirName.Count -gt 0){ $allPrograms += $dirName[0] + "\*"}
                }
            }
        }

        $roots = $drives | Where-Object { $_.Description -ne "Temporary Storage" -and $_.Name -ne "Temp"  -and $_.Name -ne $Env:HOMEDRIVE.Substring(0,1)} | Select-Object -ExpandProperty Root
        If ($roots)
        {
            Foreach ($root in $roots)
            { 
                $dirs = Get-ChildItem $root | Where-Object { $_.Name -ne "Windows" } | Select-Object -ExpandProperty FullName
                Foreach ($dir in $dirs)
                {
                    $directory = Get-ChildItem $dir -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object DirectoryName | Select-Object -Unique | Select-Object -ExpandProperty DirectoryName
                    If ($directory.Count -gt 0) { $allPrograms += $directory + "\*" }
                }
            }
        }

        $allPrograms = $allPrograms -cnotmatch "internet explorer" | Select-Object -Unique | Sort-Object

        $filePathRule = $xml.AppLockerPolicy.SelectSingleNode("RuleCollection[@Type='Exe']")
        Foreach ($path in $allPrograms)
        {
            $guid = (New-Guid).Guid
            $filePathRuleElm = $xml.CreateElement("FilePathRule")
            $filePathRuleElm.SetAttribute("Id","$guid")
            $filePathRuleElm.SetAttribute("Name","$path")
            $filePathRuleElm.SetAttribute("Description","")
            $filePathRuleElm.SetAttribute("UserOrGroupSid","S-1-1-0")
            $filePathRuleElm.SetAttribute("Action","Allow")
            $filePathRule.AppendChild($filePathRuleElm) | Out-Null

            $condition = $xml.SelectSingleNode("//*[@Id=`"$guid`"]")
            $conElm = $xml.CreateElement("Conditions")
            $condition.AppendChild($conElm) | Out-Null

            $filePathCon = $xml.CreateElement("FilePathCondition")
            $filePathCon.SetAttribute("Path","$path")
            $filePathConElm = $xml.SelectSingleNode("//*[@Id=`"$guid`"]").SelectSingleNode("Conditions")
            $filePathConElm.AppendChild($filePathCon) | Out-Null
        }

        $ruleCollExtElm = $xml.CreateNode("element","RuleCollectionExtensions","")
        $filePathRule.AppendChild($ruleCollExtElm) | Out-Null

        $ruleCollExt = $xml.SelectSingleNode("//*/RuleCollectionExtensions")
        $ruleCollExtElm = $xml.CreateNode("element","ThresholdExtensions","")
        $ruleCollExt.AppendChild($ruleCollExtElm) | Out-Null

        $ruleCollExt = $xml.SelectSingleNode("//*/RuleCollectionExtensions")
        $ruleCollExtElm = $xml.CreateNode("element","RedstoneExtensions","")
        $ruleCollExt.AppendChild($ruleCollExtElm) | Out-Null

        $thresExt = $xml.SelectSingleNode("//*/ThresholdExtensions")
        $servicesElm = $xml.CreateNode("element","Services","")
        $servicesElm.SetAttribute("EnforcementMode","Enabled")
        $thresExt.AppendChild($servicesElm) | Out-Null

        $xml.Save($outputFile)

        If ($SetLocalPolicy.IsPresent) {
            Set-AppLockerPolicy -XmlPolicy $outputFile
        }
    }
    
    End {
        
    }
}