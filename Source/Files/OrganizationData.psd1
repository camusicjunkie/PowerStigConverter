# Per rule type: the rule and org node property names the value is read from, plus the org node
# attributes that type's task actually consumes.
#
# Required and Optional name attributes of the OrganizationalSetting node, which are not always
# the names the generated task uses for them - IisLogging reads LogTargetW3C and
# LogCustomFieldEntry off the node and reports them as LogTarget and LogCustomFields.
#
# The completeness check and the generators both read Required from here, so a field a task
# consumes cannot be left out of the check by forgetting to add it in two places.
@{
    'AccountPolicy' = @{
        'Name' = 'PolicyName'
        'Value' = 'PolicyValue'
        'Required' = @('PolicyValue')
        'Optional' = @()
    }
    'Registry' = @{
        'Name' = 'ValueName'
        'Value' = 'ValueData'
        'Required' = @('ValueData')
        'Optional' = @()
    }
    'SecurityOption' = @{
        'Name' = 'OptionName'
        'Value' = 'OptionValue'
        'Required' = @('OptionValue')
        'Optional' = @()
    }
    'UserRight' = @{
        'Name' = 'DisplayName'
        'Value' = 'Identity'
        'Required' = @('Identity')
        'Optional' = @()
    }
    'RootCertificate' = @{
        'Value' = 'Location'
        'Required' = @('Location')
        'Optional' = @()
    }
    'Service' = @{
        'Value' = 'ServiceName'
        # The task names the service and asserts its startup type; neither is optional.
        'Required' = @('ServiceName', 'StartupType')
        'Optional' = @()
    }
    'IisLogging' = @{
        'Value' = 'LogFlags'
        # LogCustomFieldEntry is genuinely optional - New-AnsibleIisLoggingTask already omits the
        # LogCustomFields property from the DSC task when it is empty.
        'Required' = @('LogFlags', 'LogFormat', 'LogPeriod', 'LogTargetW3C')
        'Optional' = @('LogCustomFieldEntry')
    }
}
