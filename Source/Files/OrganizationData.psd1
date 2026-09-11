# Per rule type: the rule and org node property names the value is read from, plus the org node
# attributes that type's task actually consumes.
#
# Required and List name attributes of the OrganizationalSetting node, which are not always
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
    }
    'Registry' = @{
        'Name' = 'ValueName'
        'Value' = 'ValueData'
        'Required' = @('ValueData')
    }
    'SecurityOption' = @{
        'Name' = 'OptionName'
        'Value' = 'OptionValue'
        'Required' = @('OptionValue')
    }
    'UserRight' = @{
        'Name' = 'DisplayName'
        'Value' = 'Identity'
        'Required' = @('Identity')
        # win_user_right takes a list of identities, so the variable holds one.
        'List' = @('Identity')
    }
    'RootCertificate' = @{
        'Value' = 'Location'
        'Required' = @('Location')
    }
    'Service' = @{
        'Value' = 'ServiceName'
        # The task names the service and asserts its startup type; neither is optional.
        'Required' = @('ServiceName', 'StartupType')
    }
    'IisLogging' = @{
        'Value' = 'LogFlags'
        # LogCustomFieldEntry is deliberately absent: New-AnsibleIisLoggingTask already omits the
        # LogCustomFields property from the DSC task when it is empty, so requiring it would
        # refuse a conversion that has everything it needs.
        'Required' = @('LogFlags', 'LogFormat', 'LogPeriod', 'LogTargetW3C')
        # The DSC resource takes these two as lists.
        'List' = @('LogFlags', 'LogTargetW3C')
    }
}
