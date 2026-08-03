@{
    RootModule = 'CaseKit.psm1'
    ModuleVersion = '0.1.0'
    GUID = '2e5a137d-6831-4c31-9a4c-7d96f6c67810'
    Author = 'Dark Passenger contributors'
    Description = 'Reusable build-time case authoring and compilation core.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'ConvertTo-CaseKitBackendInput',
        'Read-CaseKitAuthoringDeck',
        'Resolve-CaseKitVariants'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
