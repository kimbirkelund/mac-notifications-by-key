# PSScriptAnalyzer settings. Formatting rules mirror the PowerShell editor
# settings in ../profile/.vscode/settings.json (Allman preset, open brace on a new
# line, correct casing, alias auto-correction, constant strings, whitespace between
# parameters, first-pipeline indentation). Default best-practice rules are also run.
@{
    IncludeDefaultRules = $true

    ExcludeRules        = @(
        # Write-Host is intentional for the build script's colored progress output.
        'PSAvoidUsingWriteHost'
        # False positives: does not detect script-scope params used inside nested
        # functions (e.g. $Quiet read inside Write-Step).
        'PSReviewUnusedParameter'
    )

    Rules               = @{
        # preset: Allman + openBraceOnSameLine: false
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $false
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        # pipelineIndentationStyle: IncreaseIndentationForFirstPipeline (2-space)
        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            IndentationSize     = 2
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
        # trimWhitespaceAroundPipe + whitespaceBetweenParameters
        PSUseConsistentWhitespace  = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator                  = $true
            CheckParameter                  = $true
        }
        # useCorrectCasing
        PSUseCorrectCasing         = @{
            Enable = $true
        }
        # autoCorrectAliases
        PSAvoidUsingCmdletAliases  = @{
            Enable = $true
        }
        # useConstantStrings
        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }
    }
}
