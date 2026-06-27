BeforeAll {
    Import-Module "$PSScriptRoot\..\McSync.psm1" -Force
}

Describe 'Get-FileIndex' {
    BeforeEach {
        New-Item -ItemType Directory -Path "$TestDrive\sub" -Force | Out-Null
        Set-Content "$TestDrive\file.txt"       "hello"
        Set-Content "$TestDrive\sub\data.json"  '{"key":"value"}'
        [System.IO.File]::WriteAllBytes("$TestDrive\image.png", [byte[]](0x89, 0x50, 0x4E, 0x47))
    }

    It 'returns relative paths as keys' {
        $index = Get-FileIndex -Path $TestDrive
        $index.Keys | Should -Contain 'file.txt'
        $index.Keys | Should -Contain 'sub\data.json'
    }

    It 'uses SHA256 hash for text files' {
        $index    = Get-FileIndex -Path $TestDrive
        $expected = (Get-FileHash "$TestDrive\file.txt" -Algorithm SHA256).Hash
        $index['file.txt'] | Should -Be $expected
    }

    It 'uses file size for binary files' {
        $index = Get-FileIndex -Path $TestDrive
        $size  = (Get-Item "$TestDrive\image.png").Length
        $index['image.png'] | Should -Be $size
    }

    It 'returns empty hashtable for empty directory' {
        $empty = New-Item -ItemType Directory -Path "$TestDrive\empty" -Force
        $index = Get-FileIndex -Path $empty.FullName
        $index.Count | Should -Be 0
    }

    It 'returns empty hashtable for missing path' {
        $index = Get-FileIndex -Path "$TestDrive\nonexistent"
        $index.Count | Should -Be 0
    }
}

Describe 'Get-SyncDiff' {
    It 'marks new local files as ToCopy' {
        $diff = Get-SyncDiff -LocalIndex @{ 'a.txt' = 'H1' } -RemoteIndex @{}
        $diff.ToCopy   | Should -Contain 'a.txt'
        $diff.ToDelete | Should -HaveCount 0
    }

    It 'marks changed files as ToCopy' {
        $diff = Get-SyncDiff -LocalIndex @{ 'a.txt' = 'NEW' } -RemoteIndex @{ 'a.txt' = 'OLD' }
        $diff.ToCopy | Should -Contain 'a.txt'
    }

    It 'skips unchanged files' {
        $diff = Get-SyncDiff -LocalIndex @{ 'a.txt' = 'SAME' } -RemoteIndex @{ 'a.txt' = 'SAME' }
        $diff.ToCopy   | Should -HaveCount 0
        $diff.ToDelete | Should -HaveCount 0
    }

    It 'marks remote-only files as ToDelete' {
        $diff = Get-SyncDiff -LocalIndex @{} -RemoteIndex @{ 'old.txt' = 'H1' }
        $diff.ToDelete | Should -Contain 'old.txt'
        $diff.ToCopy   | Should -HaveCount 0
    }

    It 'handles copy and delete in the same diff' {
        $diff = Get-SyncDiff `
            -LocalIndex  @{ 'new.txt' = 'H1' } `
            -RemoteIndex @{ 'old.txt' = 'H2' }
        $diff.ToCopy   | Should -Contain 'new.txt'
        $diff.ToDelete | Should -Contain 'old.txt'
    }
}

Describe 'Get-InstanceJavaPaths' {
    BeforeEach {
        New-Item -ItemType Directory -Path "$TestDrive\inst" -Force | Out-Null
    }

    It 'reads JavaPath from instance.cfg' {
        Set-Content "$TestDrive\inst\instance.cfg" "[General]`nJavaPath=C:\Java\java.exe`nname=Test"
        $result = Get-InstanceJavaPaths -BasePath $TestDrive -CfgRelPaths @('inst\instance.cfg')
        $result['inst\instance.cfg'] | Should -Be 'JavaPath=C:\Java\java.exe'
    }

    It 'returns empty when no JavaPath line' {
        Set-Content "$TestDrive\inst\instance.cfg" "[General]`nname=Test"
        $result = Get-InstanceJavaPaths -BasePath $TestDrive -CfgRelPaths @('inst\instance.cfg')
        $result.Count | Should -Be 0
    }

    It 'skips missing cfg files' {
        $result = Get-InstanceJavaPaths -BasePath $TestDrive -CfgRelPaths @('inst\missing.cfg')
        $result.Count | Should -Be 0
    }
}

Describe 'Restore-InstanceJavaPaths' {
    BeforeEach {
        New-Item -ItemType Directory -Path "$TestDrive\inst" -Force | Out-Null
    }

    It 'inserts JavaPath after [General]' {
        Set-Content "$TestDrive\inst\instance.cfg" "[General]`nname=Test"
        Restore-InstanceJavaPaths -BasePath $TestDrive -JavaPaths @{ 'inst\instance.cfg' = 'JavaPath=C:\Java\java.exe' }
        $content = Get-Content "$TestDrive\inst\instance.cfg"
        $content.IndexOf('JavaPath=C:\Java\java.exe') | Should -BeGreaterThan ($content.IndexOf('[General]'))
    }

    It 'adds [General] section when missing' {
        Set-Content "$TestDrive\inst\instance.cfg" "name=Test"
        Restore-InstanceJavaPaths -BasePath $TestDrive -JavaPaths @{ 'inst\instance.cfg' = 'JavaPath=C:\Java\java.exe' }
        $content = Get-Content "$TestDrive\inst\instance.cfg"
        $content | Should -Contain '[General]'
        $content | Should -Contain 'JavaPath=C:\Java\java.exe'
    }

    It 'replaces an existing JavaPath' {
        Set-Content "$TestDrive\inst\instance.cfg" "[General]`nJavaPath=C:\OldJava\java.exe`nname=Test"
        Restore-InstanceJavaPaths -BasePath $TestDrive -JavaPaths @{ 'inst\instance.cfg' = 'JavaPath=C:\NewJava\java.exe' }
        $content = Get-Content "$TestDrive\inst\instance.cfg"
        $content | Should -Contain 'JavaPath=C:\NewJava\java.exe'
        $content | Should -Not -Contain 'JavaPath=C:\OldJava\java.exe'
    }

    It 'skips missing files silently' {
        { Restore-InstanceJavaPaths -BasePath $TestDrive -JavaPaths @{ 'inst\missing.cfg' = 'JavaPath=C:\Java\java.exe' } } | Should -Not -Throw
    }
}
