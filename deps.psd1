@{
    BuildBranch = 'v0.60d'

    Workspace = @{
        LogsRoot = 'logs'
        Toolchain = @{
            WindowsTargetPlatformVersion = '10.0'
            ToolsetOverrideVariable = 'EMULE_V060_PLATFORM_TOOLSET'
        }
        AppRepo = @{
            SeedRepo = 'eMule-v0.60d-oracle'
            Variants = @(
                @{ Name = 'build'; Branch = 'v0.60d-build'; Path = 'eMule-v0.60d-build' }
                @{ Name = 'dev'; Branch = 'v0.60d-dev'; Path = 'eMule-v0.60d-dev' }
                @{ Name = 'oracle'; Branch = 'v0.60d-oracle'; Path = 'eMule-v0.60d-oracle' }
            )
        }
        Dependencies = @(
            @{
                Name = 'cryptopp'
                Repo = 'eMule-cryptopp-8.4.0'
                Url = 'https://github.com/itlezy/eMule-cryptopp.git'
                Branch = 'CRYPTOPP_8_4_0-eMule'
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
                BuildScript = @{
                    Release = 'build_MSBuild_eMule-zlib-1.2.12.cmd'
                    Debug = 'build_MSBuild_eMule-zlib-1.2.12_debug.cmd'
                }
            }
        )
    }
}
