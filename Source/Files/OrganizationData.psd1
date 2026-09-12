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
        # PowerStig spells 'nobody holds this right' as the string NULL.
        'Empty' = 'NULL'
    }
    'RootCertificate' = @{
        'Value' = 'Location'
        'Required' = @('Location')
        # One store path (Cert:\LocalMachine\Root) answers two win_certificate_info
        # parameters, so it becomes two variables named for them. See #4.
        'Part' = @{
            'Location' = @('store_name', 'store_location')
        }
        # How each part is taken out of the path it shares.
        'Derive' = @{
            'store_name' = 'Leaf'
            'store_location' = 'ParentLeaf'
        }
        # The task consumes an object, not a scalar. Keys are what the task reads, values are
        # the part or org node attribute each comes from.
        'Shape' = @{
            'StoreName' = 'store_name'
            'StoreLocation' = 'store_location'
        }
    }
    'Service' = @{
        'Value' = 'ServiceName'
        # The task names the service and asserts its startup type; neither is optional.
        'Required' = @('ServiceName', 'StartupType')
        'Shape' = @{
            'ServiceName' = 'ServiceName'
            'StartupType' = 'StartupType'
        }
    }
    'IisLogging' = @{
        'Value' = 'LogFlags'
        # LogCustomFieldEntry is deliberately absent: New-AnsibleIisLoggingTask already omits the
        # LogCustomFields property from the DSC task when it is empty, so requiring it would
        # refuse a conversion that has everything it needs.
        'Required' = @('LogFlags', 'LogFormat', 'LogPeriod', 'LogTargetW3C')
        # The DSC resource takes these two as lists.
        'List' = @('LogFlags', 'LogTargetW3C')
        # LogTarget and LogCustomFields are what the task reads; the org node calls them
        # LogTargetW3C and LogCustomFieldEntry.
        'Shape' = @{
            'LogFlags' = 'LogFlags'
            'LogFormat' = 'LogFormat'
            'LogPeriod' = 'LogPeriod'
            'LogTarget' = 'LogTargetW3C'
            'LogCustomFields' = 'LogCustomFieldEntry'
        }
    }
}
