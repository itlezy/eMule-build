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
            CompareSubdir = 'srchybrid'
            Variants = @(
                @{ Name = 'build'; Branch = 'v0.60d-build-clean'; Path = 'eMule-v0.60d-build-clean'; Mutability = 'frozen' }
                @{ Name = 'bugfix'; Branch = 'v0.60d-bugfix-clean'; Path = 'eMule-v0.60d-bugfix-clean'; Mutability = 'frozen' }
                @{ Name = 'broadband'; Branch = 'v0.60d-broadband-clean'; Path = 'eMule-v0.60d-broadband-clean'; Mutability = 'frozen' }
                @{ Name = 'experimental'; Branch = 'v0.60d-experimental-clean'; Path = 'eMule-v0.60d-experimental-clean'; Mutability = 'editable' }
            )
        }
        Package = @{
            Release = @{
                SourceProject = 'eMule'
                OutputDir = 'dist'
                ArchiveName = 'eMule0.60d-build_x64-snapshot.zip'
                RootDir = 'eMule0.60d-build_x64'
                BuildInfoName = 'BUILD-INFO.txt'
                Entry = 'emule.exe'
                Include = @(
                    @{
                        Source = 'LICENSE'
                        Destination = 'LICENSE'
                    }
                )
            }
        }
        GeneratedProjects = @{
            zlib = @{
                ConfigureReady = @(
                    'eMule-zlib-1.2.12\contrib\vstudio\vc17\zlibstat.vcxproj'
                )
            }
            mbedtls = @{
                ConfigureReady = @(
                    'eMule-mbedtls-2.28\visualc\VS2010\mbedTLS.vcxproj'
                    'eMule-mbedtls-2.28\visualc\VS2010\mbedTLS.sln'
                )
            }
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

    DependencyOrder = @(
        'cryptopp'
        'cximage'
        'id3lib'
        'libpng'
        'mbedtls'
        'miniupnp'
        'ResizableLib'
        'zlib'
    )

    BuildProjects = @(
        'cryptopp'
        'cximage'
        'id3lib'
        'libpng'
        'mbedtls'
        'miniupnp'
        'ResizableLib'
        'zlib'
    )

    Projects = @{
        cryptopp = @{
            Kind   = 'msbuild'
            Path   = 'eMule-cryptopp-8.4.0\cryptlib.vcxproj'
            Output = @{
                Release = 'eMule-cryptopp-8.4.0\x64\Output\Release\cryptlib.lib'
                Debug   = 'eMule-cryptopp-8.4.0\x64\Output\Debug\cryptlib.lib'
            }
            Open = 'eMule-cryptopp-8.4.0\cryptlib.vcxproj'
        }
        cximage = @{
            Kind   = 'msbuild'
            Path   = 'eMule-CxImage-7.02\CxImage\cximage.vcxproj'
            Output = @{
                Release = 'eMule-CxImage-7.02\CxImage\x64\Release\cximage.lib'
                Debug   = 'eMule-CxImage-7.02\CxImage\x64\Debug\cximage.lib'
            }
            Open = 'eMule-CxImage-7.02\CxImage\cximage.vcxproj'
        }
        id3lib = @{
            Kind   = 'msbuild'
            Path   = 'eMule-id3lib-3.9.1\libprj\id3lib.vcxproj'
            Output = @{
                Release = 'eMule-id3lib-3.9.1\libprj\x64\Release\id3lib.lib'
                Debug   = 'eMule-id3lib-3.9.1\libprj\x64\Debug\id3lib.lib'
            }
            Open = 'eMule-id3lib-3.9.1\libprj\id3lib.vcxproj'
        }
        libpng = @{
            Kind   = 'msbuild'
            Path   = 'eMule-libpng-1.5.30\projects\vstudio\vstudio.sln'
            Output = @{
                Release = 'eMule-libpng-1.5.30\projects\vstudio\x64\Release Library\libpng15.lib'
                Debug   = 'eMule-libpng-1.5.30\projects\vstudio\x64\Debug Library\libpng15.lib'
            }
            Open = 'eMule-libpng-1.5.30\projects\vstudio\vstudio.sln'
        }
        mbedtls = @{
            Kind   = 'msbuild'
            Path   = 'eMule-mbedtls-2.28\visualc\VS2010\mbedTLS.vcxproj'
            Output = @{
                Release = 'eMule-mbedtls-2.28\visualc\VS2010\x64\Release\mbedTLS.lib'
                Debug   = 'eMule-mbedtls-2.28\visualc\VS2010\x64\Debug\mbedTLS.lib'
            }
            Open = 'eMule-mbedtls-2.28\visualc\VS2010\mbedTLS.vcxproj'
        }
        miniupnp = @{
            Kind   = 'msbuild'
            Path   = 'eMule-miniupnp-2.2.3\miniupnpc\msvc\miniupnpc.vcxproj'
            Output = @{
                Release = 'eMule-miniupnp-2.2.3\miniupnpc\msvc\x64\Release\miniupnpc.lib'
                Debug   = 'eMule-miniupnp-2.2.3\miniupnpc\msvc\x64\Debug\miniupnpc.lib'
            }
            Open = 'eMule-miniupnp-2.2.3\miniupnpc\msvc\miniupnpc.vcxproj'
        }
        ResizableLib = @{
            Kind   = 'msbuild'
            Path   = 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj'
            Output = @{
                Release = 'eMule-ResizableLib\ResizableLib\x64\Release Static\ResizableLib.lib'
                Debug   = 'eMule-ResizableLib\ResizableLib\x64\Debug Static\ResizableLib.lib'
            }
            Open = 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj'
        }
        zlib = @{
            Kind   = 'msbuild'
            Path   = 'eMule-zlib-1.2.12\contrib\vstudio\vc17\zlibstat.vcxproj'
            Output = @{
                Release = 'eMule-zlib-1.2.12\contrib\vstudio\vc17\x64\ZlibStatRelease\zlibstat.lib'
                Debug   = 'eMule-zlib-1.2.12\contrib\vstudio\vc17\x64\ZlibStatDebug\zlibstat.lib'
            }
            Open = 'eMule-zlib-1.2.12\contrib\vstudio\vc17\zlibstat.vcxproj'
        }
        eMule = @{
            Kind   = 'msbuild'
            Path   = 'eMule-v0.60d-build-clean\srchybrid\emule.vcxproj'
            Output = @{
                Release = 'eMule-v0.60d-build-clean\srchybrid\x64\Release\emule.exe'
                Debug   = 'eMule-v0.60d-build-clean\srchybrid\x64\Debug\emule.exe'
            }
            Open = 'eMule-v0.60d-build-clean\srchybrid\emule.sln'
        }
    }
}
