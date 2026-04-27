@{
    Workspace = @{
        Name = 'v0.72a'
        Toolchain = @{
            ToolsetOverrideVariable = 'EMULE_V072_PLATFORM_TOOLSET'
        }
        AppRepo = @{
            TestTargets = @{
                TestBuildVariant = 'community'
                TestRunVariant = 'main'
                BaselineVariant = 'community'
            }
        }
        Dependencies = @(
            @{
                Name = 'cryptopp'
                Path = 'repos\third_party\eMule-cryptopp'
                Project = 'cryptlib.vcxproj'
            }
            @{
                Name = 'id3lib'
                Path = 'repos\third_party\eMule-id3lib'
                Project = 'libprj\id3lib.vcxproj'
            }
            @{
                Name = 'libpcpnatpmp'
                Path = 'repos\third_party\eMule-libpcpnatpmp'
                Project = 'CMakeLists.txt'
            }
            @{
                Name = 'miniupnp'
                Path = 'repos\third_party\eMule-miniupnp'
                Project = 'miniupnpc\msvc\miniupnpc.vcxproj'
            }
            @{
                Name = 'ResizableLib'
                Path = 'repos\third_party\eMule-ResizableLib'
                Project = 'ResizableLib\ResizableLib.vcxproj'
            }
            @{
                Name = 'zlib'
                Path = 'repos\third_party\eMule-zlib'
                Project = 'contrib\vstudio\vc\zlib.vcxproj'
            }
            @{
                Name = 'mbedtls'
                Path = 'repos\third_party\eMule-mbedtls'
                Project = 'visualc\VS2017\mbedTLS.vcxproj'
            }
        )
    }
}
