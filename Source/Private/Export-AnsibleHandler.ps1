function Export-AnsibleHandler {
    <#
    .SYNOPSIS
        Collects the handlers the generated tasks notify, one entry per distinct handler.
    .DESCRIPTION
        A handler is shared: every rule of a type that needs one builds the same handler and
        notifies it by name, so the same handler arrives once per rule and is written once.

        Always produces a file, even when nothing generated a handler, because handlers/main.yml
        imports it statically and an import of a file that is not there fails the play.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Task
    )

    begin {
        $handlers = [ordered] @{}
    }
    process {
        foreach ($handler in @($Task.Handler)) {
            if ($null -eq $handler) { continue }

            $yaml = ConvertTo-Yaml $handler -KeepArray

            if (-not $handlers.Contains($handler.name)) {
                $handlers[$handler.name] = $yaml
                Write-Verbose "  Handler: $($handler.name)"
                continue
            }

            # A notify names one handler, so two different writes under one name means the one
            # that lost silently never runs - louder here than in the generated role.
            if ($handlers[$handler.name] -ne $yaml) {
                throw "Two different handlers are named $($handler.name); a notify can only reach one of them."
            }
        }
    }
    end {
        $content = if ($handlers.Count -gt 0) {
            $handlers.Values
        }
        else {
            # A valid, empty handler list rather than an empty file: yaml reads this as no
            # handlers, where nothing at all is a parse the import cannot be relied on to survive.
            @('# No rule in this STIG generates a handler.', '[]')
        }

        [ordered] @{ generated = $content }
    }
}
