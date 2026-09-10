function Get-AnsibleInheritanceFlag {
    [CmdletBinding()]
    param (
        [string] $Resource,

        [string] $Inheritance
    )

    switch ($Resource) {
        'NTFSAccessEntry' {
            switch ($Inheritance) {
                'This folder only' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 0
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
                'This folder subfolders and files' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 3
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
                'This folder and subfolders' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 1
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
                'This folder and files' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 2
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
                'Subfolders and files only' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 3
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 2
                    break
                }
                'Subfolders only' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 1
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 2
                    break
                }
                'Files only' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 2
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 2
                    break
                }
                default {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 0
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
            }
        }

        'RegistryAccessEntry' {
            switch ($Inheritance) {
                'This Key Only' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 0
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
                'This Key and Subkeys' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 1
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
                'Subkeys Only' {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 1
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 2
                    break
                }
                default {
                    $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags] 1
                    $propagationFlag = [System.Security.AccessControl.PropagationFlags] 0
                    break
                }
            }
        }
    }

    [pscustomobject] @{
        InheritanceFlag = $inheritanceFlag
        PropagationFlag = $propagationFlag
    }
}
