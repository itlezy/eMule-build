@{
    BuildBranch = 'v0.60d-build-clean'

    Workspace = @{
        LogsRoot = 'logs'
        Toolchain = @{
            WindowsTargetPlatformVersion = '10.0'
            ToolsetOverrideVariable = 'EMULE_V060_PLATFORM_TOOLSET'
        }
        AppRepo = @{
            SeedRepo = @{
                Path = 'eMule-v0.60d-build-clean'
                Url = 'https://github.com/itlezy/eMule.git'
                Branch = 'v0.60d-build-clean'
            }
            Variants = @(
                @{ Name = 'build'; Branch = 'v0.60d-build-clean'; Path = 'eMule-v0.60d-build-clean' }
                @{ Name = 'bugfix'; Branch = 'v0.60d-bugfix-clean'; Path = 'eMule-v0.60d-bugfix-clean' }
                @{ Name = 'broadband'; Branch = 'v0.60d-broadband-clean'; Path = 'eMule-v0.60d-broadband-clean' }
                @{ Name = 'experimental'; Branch = 'v0.60d-experimental-clean'; Path = 'eMule-v0.60d-experimental-clean' }
            )
        }
        Dependencies = @(
            @{
                Name = 'cryptopp'
                Repo = 'eMule-cryptopp-8.4.0'
                Url = 'https://github.com/itlezy/eMule-cryptopp.git'
                Branch = 'CRYPTOPP_8_4_0-eMule'
                Commit = '8f353efd689beaebeb53155c3adbb0189ff2d0f4'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-cryptopp-8.4.0.cmd'
                    Debug = 'build_MSBuild_eMule-cryptopp-8.4.0_debug.cmd'
                }
            }
            @{
                Name = 'cximage'
                Repo = 'eMule-CxImage-7.02'
                Url = 'https://github.com/itlezy/eMule-CxImage.git'
                Branch = 'master'
                Commit = '8fcd7e59d367fdfa76c1a707c79157fd3f3e5d1b'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-CxImage-7.02.cmd'
                    Debug = 'build_MSBuild_eMule-CxImage-7.02_debug.cmd'
                }
            }
            @{
                Name = 'id3lib'
                Repo = 'eMule-id3lib-3.9.1'
                Url = 'https://github.com/itlezy/eMule-id3lib.git'
                Branch = 'v3.9.1'
                Commit = 'd218203f18ea6c64fa0c3f3523bb74bef8b3bea2'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-id3lib-3.9.1.cmd'
                    Debug = 'build_MSBuild_eMule-id3lib-3.9.1_debug.cmd'
                }
            }
            @{
                Name = 'libpng'
                Repo = 'eMule-libpng-1.5.30'
                Url = 'https://github.com/itlezy/eMule-libpng.git'
                Branch = '1.5.30-eMule'
                Commit = 'd47ddef73d84ee8c8c30a2ad26af39ceda7abc29'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-libpng-1.5.30.cmd'
                    Debug = 'build_MSBuild_eMule-libpng-1.5.30_debug.cmd'
                }
            }
            @{
                Name = 'mbedtls'
                Repo = 'eMule-mbedtls-2.28'
                Url = 'https://github.com/itlezy/eMule-mbedtls.git'
                Branch = 'mbedtls-2.28-eMule'
                Commit = '58a1f4eefc31ff9cb2a9df4843ffe63c5f1dfaa1'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-mbedtls-2.28.cmd'
                    Debug = 'build_MSBuild_eMule-mbedtls-2.28_debug.cmd'
                }
            }
            @{
                Name = 'miniupnp'
                Repo = 'eMule-miniupnp-2.2.3'
                Url = 'https://github.com/itlezy/eMule-miniupnp.git'
                Branch = 'miniupnpc_2_2_3-eMule'
                Commit = '29311b2b60d7b04525d21bcf399fb28d24a46226'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-miniupnp-2.2.3.cmd'
                    Debug = 'build_MSBuild_eMule-miniupnp-2.2.3_debug.cmd'
                }
            }
            @{
                Name = 'ResizableLib'
                Repo = 'eMule-ResizableLib'
                Url = 'https://github.com/itlezy/eMule-ResizableLib.git'
                Branch = 'master'
                Commit = 'f9b885c1752c2d965f0d98c627cdacc23a6f3afe'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-ResizableLib.cmd'
                    Debug = 'build_MSBuild_eMule-ResizableLib_debug.cmd'
                }
            }
            @{
                Name = 'zlib'
                Repo = 'eMule-zlib-1.2.12'
                Url = 'https://github.com/itlezy/eMule-zlib.git'
                Branch = 'v1.2.12-eMule'
                Commit = '390e3bc393d1bd797692e664870ad30472ab65f8'
                Required = $true
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-zlib-1.2.12.cmd'
                    Debug = 'build_MSBuild_eMule-zlib-1.2.12_debug.cmd'
                }
            }
        )
    }
}
