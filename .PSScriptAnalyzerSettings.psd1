# Rule design is provided based on https://github.com/PowerShell/PSScriptAnalyzer/tree/master/RuleDocumentation
@{
    # Process ONLY the following rules
    IncludeRules = @(
        # General
        'PSAvoidDefaultValueSwitchParameter',
        'PSAvoidDefaultValueForMandatoryParameter',
        'PSAvoidAssignmentToAutomaticVariable',
        'PSMissingModuleManifestField',
        'PSPossibleIncorrectComparisonWithNull',
        'PSPossibleIncorrectUsageOfRedirectionOperator',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSShouldProcess',
        'PSUseApprovedVerbs',
        'PSUseToExportFieldsInManifest',
        'PSUseUsingScopeModifierInNewRunspaces',

        # Security
        'PSAvoidUsingComputerNameHardcoded',

        # Code style
        'PSAvoidLongLines',
        'PSAvoidTrailingWhitespace',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingDoubleQuotesForConstantString',
        'PSProvideCommentHelp',
        'PSPossibleIncorrectUsageOfAssignmentOperator',
        'PSPossibleIncorrectUsageOfRedirectionOperator',
        'PSMisleadingBacktick',
        'PSUseLiteralInitializerForHashtable',

        # Code formatting OTBS
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseConsistentWhitespace',
        'PSUseConsistentIndentation',
        'PSAlignAssignmentStatement',
        'PSUseCorrectCasing',

        # Functions
        'PSAvoidUsingWMICmdlet',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingPositionalParameters',
        'PSReservedCmdletChar',
        'PSReservedParams',
        # 'PSReviewUnusedParameter',
        'PSUseCmdletCorrectly',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseSingularNouns',
        'PSUseOutputTypeCorrectly'
    )
    # Configuration for the rules defined above
    Rules        = @{
        # Code style
        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }

        # Code formatting OTBS
        PSPlaceOpenBrace                          = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace                         = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        PSUseConsistentIndentation                = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        PSUseConsistentWhitespace                 = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $false # https://github.com/PowerShell/PSScriptAnalyzer/issues/769
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator                  = $true
            CheckParameter                  = $true
        }

        PSAlignAssignmentStatement                = @{
            Enable         = $true
            CheckHashtable = $true
        }

        PSUseCorrectCasing                        = @{
            Enable = $true
        }
    }
}