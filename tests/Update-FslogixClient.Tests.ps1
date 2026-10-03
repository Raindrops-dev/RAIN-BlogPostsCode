# Requires Pester 5. Run: Invoke-Pester ./tests/Update-FslogixClient.Tests.ps1 -Output Detailed
# Tests load definitions and the update workflow from the AST, never the live script.
# Registry reads, downloads, extraction, cleanup and installer execution are mocked.

BeforeAll {
    $SourcePath = Join-Path $PSScriptRoot '../Update-FslogixClient.ps1'
    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($SourcePath, [ref]$Tokens, [ref]$ParseErrors)
    if ($ParseErrors.Count -gt 0) {
        throw ($ParseErrors | Out-String)
    }
    $Ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] } |
        ForEach-Object { . ([scriptblock]::Create($_.Extent.Text)) }

    # Skip only logging and real URL resolution. Execute the original workflow statements.
    $Main = @($Ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] })[0]
    $Start = @($Main.Body.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left.Extent.Text -eq '$RegPaths'
    })[0]
    if ($null -eq $Start) { throw 'Cannot locate the update workflow.' }
    $Workflow = [scriptblock]::Create(($Main.Body.Statements | Where-Object {
        $_.Extent.StartOffset -ge $Start.Extent.StartOffset
    } | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine)

    # BITS is unavailable on non-Windows test hosts. This stub must always be mocked.
    function Start-BitsTransfer {
        [CmdletBinding()]
        param($Source, $Destination, $Priority, $TransferPolicy)
        throw 'The test attempted an unmocked download.'
    }
}

Describe 'FSLogix build version parsing' {
    It 'accepts legacy and current four-part build versions' -ForEach @(
        @{ Value = '2.9.8884.27471' }
        @{ Value = '3.25.202.4223' }
        @{ Value = ' 3.25.401.15305 ' }
    ) {
        $Version = ConvertTo-FsLogixBuildVersion -Value $Value -Source 'test'
        $Version | Should -BeOfType ([version])
        $Version.ToString() | Should -Be $Value.Trim()
    }

    It 'rejects missing, release-label and malformed versions' -ForEach @(
        @{ Value = $null }
        @{ Value = '' }
        @{ Value = '25.02' }
        @{ Value = '0.0.0.0' }
        @{ Value = '3.25.202' }
        @{ Value = '3.25.202.4223-preview' }
        @{ Value = '3.25.202.999999999999999' }
    ) {
        { ConvertTo-FsLogixBuildVersion -Value $Value -Source 'test' } | Should -Throw
    }

    It 'compares build components numerically' {
        $Older = ConvertTo-FsLogixBuildVersion '3.25.99.9999' 'test'
        $Newer = ConvertTo-FsLogixBuildVersion '3.25.202.4223' 'test'
        ($Older -lt $Newer) | Should -BeTrue
    }
}

Describe 'Installed FSLogix version' {
    BeforeEach {
        Mock Test-Path { $true }
        Mock Get-ChildItem { [pscustomobject]@{ PSPath = 'mock registry entry' } }
        Mock Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Microsoft FSLogix Apps'; DisplayVersion = '3.25.202.4223' } }
    }

    It 'deduplicates matching registrations in both registry views' {
        $Version = Get-FsLogixInstalledVersion -RegistryPaths @('native', 'wow')
        $Version | Should -BeOfType ([version])
        $Version.ToString() | Should -Be '3.25.202.4223'
    }

    It 'tolerates a missing uninstall registry view' {
        Mock Test-Path { $LiteralPath -eq 'native' }
        (Get-FsLogixInstalledVersion @('native', 'wow')).ToString() | Should -Be '3.25.202.4223'
        Should -Invoke Get-ChildItem -Times 1 -Exactly
    }

    It 'fails clearly when FSLogix is absent' {
        Mock Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Other app'; DisplayVersion = '1.0.0.0' } }
        { Get-FsLogixInstalledVersion @('native') } | Should -Throw '*not installed*'
    }

    It 'rejects multiple distinct installed versions' {
        Mock Get-ItemProperty {
            [pscustomobject]@{ DisplayName = 'Microsoft FSLogix Apps'; DisplayVersion = '3.25.202.4223' }
            [pscustomobject]@{ DisplayName = 'Microsoft FSLogix Apps'; DisplayVersion = '2.9.8884.27471' }
        }
        { Get-FsLogixInstalledVersion @('native') } | Should -Throw '*multiple versions*'
    }
}

Describe 'Downloaded installer version' {
    It 'uses ProductVersion even when the archive name is only 25.02' {
        Mock Get-Item {
            [pscustomobject]@{ VersionInfo = [pscustomobject]@{ ProductVersion = '3.25.202.4223'; FileVersion = '9.9.9.9' } }
        }
        $Version = Get-FsLogixInstallerVersion -InstallerPath 'C:\temp\FSLogix_25.02\x64\Release\FSLogixAppsSetup.exe'
        $Version.ToString() | Should -Be '3.25.202.4223'
    }

    It 'rejects an installer without a valid build version' {
        Mock Get-Item { [pscustomobject]@{ VersionInfo = [pscustomobject]@{ ProductVersion = '25.02' } } }
        { Get-FsLogixInstallerVersion 'bad.exe' } | Should -Throw
    }
}

Describe 'FSLogix update workflow' {
    BeforeEach {
        $WorkingDirectory = 'C:\mock-fslogix'
        $FsLogixDownloadFilename = 'FSLogix_25.02.zip'
        $FsLogixDownloadFilenameWithoutExtension = 'FSLogix_25.02'
        $FsLogixFinalDownloadURL = 'https://example.invalid/FSLogix_25.02.zip'
        $ErrorActionPreference = 'Stop'
        $script:InstalledReads = 0
        $script:RemovedExtraction = $false
        Mock Get-FsLogixInstalledVersion { [version]'3.25.202.4223' }
        Mock Get-FsLogixInstallerVersion { [version]'3.25.202.4223' }
        Mock Test-Path { $LiteralPath -like '*FSLogixAppsSetup.exe' }
        Mock Start-BitsTransfer {}
        Mock Expand-Archive {}
        Mock Remove-Item {}
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Write-Warning {}
    }

    It 'does not reinstall build 3.25.202.4223 from release 25.02' {
        & $Workflow
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Expand-Archive -Times 1 -Exactly
        Should -Invoke Remove-Item -Times 2 -Exactly
    }

    It 'extracts a cached archive when the extraction directory is absent' {
        Mock Test-Path { $LiteralPath -like '*.zip' -or $LiteralPath -like '*FSLogixAppsSetup.exe' }
        & $Workflow
        Should -Invoke Start-BitsTransfer -Times 0 -Exactly
        Should -Invoke Expand-Archive -Times 1 -Exactly
    }

    It 'removes a stale extraction directory before expanding the archive again' {
        Mock Test-Path { $true }
        Mock Remove-Item {
            if ($LiteralPath -eq 'C:\mock-fslogix\FSLogix_25.02') { $script:RemovedExtraction = $true }
        }
        Mock Expand-Archive {
            if (-not $script:RemovedExtraction) { throw 'The stale directory was not removed before extraction.' }
        }
        & $Workflow
        Should -Invoke Start-BitsTransfer -Times 0 -Exactly
        Should -Invoke Expand-Archive -Times 1 -Exactly
        Should -Invoke Remove-Item -Times 3 -Exactly
    }

    It 'does not downgrade a newer installed build' {
        Mock Get-FsLogixInstalledVersion { [version]'3.25.401.15305' }
        & $Workflow
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'updates an older build and verifies the installed build before cleanup' -ForEach @(
        @{ ExitCode = 0 }
        @{ ExitCode = 3010 }
    ) {
        Mock Get-FsLogixInstalledVersion {
            $script:InstalledReads++
            if ($script:InstalledReads -eq 1) { [version]'2.9.8884.27471' }
            else { [version]'3.25.202.4223' }
        }
        Mock Start-Process { [pscustomobject]@{ ExitCode = $ExitCode } }
        & $Workflow
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $Wait -and $PassThru -and $ArgumentList -eq '/quiet /norestart' }
        Should -Invoke Get-FsLogixInstalledVersion -Times 2 -Exactly
        Should -Invoke Remove-Item -Times 2 -Exactly
        if ($ExitCode -eq 3010) {
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*restart is required*' }
        }
        else {
            Should -Invoke Write-Warning -Times 0 -Exactly
        }
    }

    It 'stops after a failed download and does not install or clean up' {
        Mock Start-BitsTransfer { throw 'Download failed' }
        { & $Workflow } | Should -Throw '*Download failed*'
        Should -Invoke Expand-Archive -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    It 'stops after failed extraction and does not install or clean up' {
        Mock Expand-Archive { throw 'Extraction failed' }
        { & $Workflow } | Should -Throw '*Extraction failed*'
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    It 'does not install when the extracted setup executable is missing' {
        Mock Test-Path { $false }
        { & $Workflow } | Should -Throw "*Installer doesn't exist*"
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'preserves the archive when installer metadata is invalid' {
        Mock Get-FsLogixInstallerVersion { throw 'Invalid installer metadata' }
        { & $Workflow } | Should -Throw '*Invalid installer metadata*'
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    It 'preserves diagnostic files when the installer returns a failure code' {
        Mock Get-FsLogixInstalledVersion { [version]'2.9.8884.27471' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1603 } }
        { & $Workflow } | Should -Throw '*Exit code: 1603*'
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    It 'preserves diagnostic files when the installed build does not match after setup' {
        Mock Get-FsLogixInstalledVersion { [version]'2.9.8884.27471' }
        { & $Workflow } | Should -Throw '*not the same as the downloaded build*'
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
}
