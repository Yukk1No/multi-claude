@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'   # a CLI talks to the console on purpose
    )
}
