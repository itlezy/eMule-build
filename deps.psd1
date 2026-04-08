@{
    Workspace = @{
        Name = 'v0.72a'
        Toolchain = @{
            ToolsetOverrideVariable = 'EMULE_V072_PLATFORM_TOOLSET'
        }
        AppRepo = @{
            SeedRepo = @{
                Path = 'repos\eMule'
                Branch = 'main'
            }
            Variants = @(
                @{ Name = 'main'; Branch = 'main'; Path = 'workspaces\v0.72a\app\eMule-main' }
                @{ Name = 'oracle'; Branch = 'oracle/v0.72a-build'; Path = 'workspaces\v0.72a\app\eMule-v0.72a-oracle' }
                @{ Name = 'build'; Branch = 'release/v0.72a-build'; Path = 'workspaces\v0.72a\app\eMule-v0.72a-build' }
                @{ Name = 'bugfix'; Branch = 'release/v0.72a-bugfix'; Path = 'workspaces\v0.72a\app\eMule-v0.72a-bugfix' }
            )
            TestTargets = @{
                BuildVariant = 'main'
                CoverageVariant = 'main'
                OracleVariant = 'oracle'
            }
        }
        Repos = @{
            Tests = 'repos\eMule-build-tests'
            Tooling = 'repos\eMule-tooling'
            Remote = 'repos\eMule-remote'
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
