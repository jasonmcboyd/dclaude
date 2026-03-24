BeforeAll {
    . "$PSScriptRoot/../../src/Private/Test-DClaudeSettingsSchema.ps1"
}

Describe 'Test-DClaudeSettingsSchema' {

    Context 'valid configs' {
        It 'returns no errors for a valid image registry config' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        linux = [PSCustomObject]@{ tag = 'dclaude-pwsh:latest' }
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 0
        }

        It 'returns no errors for a valid project config' {
            $config = [PSCustomObject]@{
                imageKey = 'pwsh'
                volumes  = @('C:/foo:C:/bar:ro')
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 0
        }

        It 'returns no errors for an empty config' {
            $config = [PSCustomObject]@{}
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 0
        }
    }

    Context 'invalid images property' {
        It 'reports error when images is a string' {
            $config = [PSCustomObject]@{ images = 'not-an-object' }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*images*must be an object*"
        }

        It 'reports error when image entry is not an object' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{ pwsh = 'bad' }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*pwsh*must be an object*"
        }

        It 'reports error when platform entry is not an object' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        linux = 'bad-string'
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*linux*must be an object*"
        }

        It 'reports error when tag is an empty string' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        linux = [PSCustomObject]@{ tag = '' }
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*tag*"
        }

        It 'reports error when tag is whitespace only' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        linux = [PSCustomObject]@{ tag = '  ' }
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*tag*"
        }

        It 'reports error when platform entry is missing tag' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        linux = [PSCustomObject]@{ volumes = @() }
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*tag*"
        }

        It 'reports error when volumes is not an array' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        linux = [PSCustomObject]@{ tag = 'test:latest'; volumes = 'not-array' }
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*volumes*array*"
        }

        It 'reports error when env is not an object' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    pwsh = [PSCustomObject]@{
                        linux = [PSCustomObject]@{ tag = 'test:latest'; env = 'not-object' }
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*env*object*"
        }

        It 'accepts a valid env object' {
            $config = [PSCustomObject]@{
                images = [PSCustomObject]@{
                    vertex = [PSCustomObject]@{
                        linux = [PSCustomObject]@{
                            tag = 'test:latest'
                            env = [PSCustomObject]@{ CLOUD_ML_REGION = 'us-east1' }
                        }
                    }
                }
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 0
        }
    }

    Context 'invalid top-level properties' {
        It 'reports error when image is not a string' {
            $config = [PSCustomObject]@{ image = 42 }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*image*string*"
        }

        It 'reports error when imageKey is not a string' {
            $config = [PSCustomObject]@{ imageKey = @('a', 'b') }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*imageKey*string*"
        }

        It 'reports error when top-level volumes is not an array' {
            $config = [PSCustomObject]@{ volumes = 'not-array' }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors | Should -HaveCount 1
            $errors[0] | Should -BeLike "*volumes*array*"
        }
    }

    Context 'multiple errors' {
        It 'reports all errors found' {
            $config = [PSCustomObject]@{
                images   = 'bad'
                image    = 42
                imageKey = @(1)
                volumes  = 'not-array'
            }
            $errors = Test-DClaudeSettingsSchema -Config $config -Label 'test'
            $errors.Count | Should -BeGreaterOrEqual 4
        }
    }
}
