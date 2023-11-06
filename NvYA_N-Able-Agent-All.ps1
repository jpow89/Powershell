# Function to generate a unique namespace for the New-WebServiceProxy and associated types
Function Get-NamespaceAndTypes {
    $namespace = "NAble" + ([guid]::NewGuid()).ToString().Split('-')[-1]
    $keyPairType = "$namespace.T_KeyPair"
    $keyValueType = "$namespace.T_KeyValue"

    # Return a custom object with all the necessary values
    return New-Object PSObject -Property @{
        Namespace = $namespace
        KeyPairType = $keyPairType
        KeyValueType = $keyValueType
    }
}

# Function to create a PSCredential object from given username and password
Function Get-CredentialObject {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [string]$Password
    )
    $secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
    $userNameString = [string]$Username
    return New-Object System.Management.Automation.PSCredential ($userNameString, $secpasswd)
}

# Function to connect to the N-Central server and get customer list
Function Get-CustomerList {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServerHost,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credentials,

        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )
    try {
        $bindingURL = "https://$ServerHost/dms/services/ServerEI?wsdl"
        $nws = New-WebServiceProxy -Uri $bindingURL -Credential $Credentials -Namespace $Namespace -ErrorAction Stop
        $KeyPairType = "$Namespace.T_KeyPair"
        $KeyPairs = @()
        $KeyPair = New-Object -TypeName $KeyPairType
        $KeyPair.Key = 'listSOs'
        $KeyPair.Value = "false"
        $KeyPairs += $KeyPair
        $username = $Credentials.UserName
        $password = $Credentials.GetNetworkCredential().Password
        return $nws.customerList($username, $password, $KeyPairs)
    } catch {
        Write-Error "An error occurred while trying to connect to the N-Central server: $_"
        return $null
    }
}

# Function to handle the button click event for installing the N-Able agent
Function Button-ClickEvent {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServerHost,

        [Parameter(Mandatory = $true)]
        [string]$SelectedCustomer,

        [Parameter(Mandatory = $true)]
        [string]$SelectedCustomerID
    )

    $installStatus = @{
        "Status" = $null
        "Message" = $null
    }

    try {
        $installStatus.Status = "Started"
        $installStatus.Message = "Installing, please wait..."
        Update-StatusLabel $installStatus.Message  # Assuming you have a function to update a status label.

        $uri = "https://$ServerHost/download/current/winnt/N-central/WindowsAgentSetup.exe"
        $localPath = "C:\temp\WindowsAgentSetup.exe"
        Invoke-WebRequest -Uri $uri -OutFile $localPath -ErrorAction Stop

        $parms = @(
            '/s', '/v', '/qn',
            "SERVERPROTOCOL=HTTPS",
            "SERVERADDRESS=$ServerHost",
            "SERVERPORT=443",
            "CUSTOMERID=$SelectedCustomerID",
            "CUSTOMERNAME=`"$SelectedCustomer`""
        )

        Start-Process -FilePath $localPath -ArgumentList $parms -Wait -ErrorAction Stop

        $installStatus.Status = "Completed"
        $installStatus.Message = "Installation Completed!"
        Update-StatusLabel $installStatus.Message  # Update the status label to show completion.
    } catch {
        $installStatus.Status = "Failed"
        $installStatus.Message = "Installation failed: $_"
        Update-StatusLabel $installStatus.Message  # Update the status label to show the error.
    } finally {
        # Cleanup if necessary
        if (Test-Path $localPath) {
            Remove-Item $localPath -ErrorAction SilentlyContinue
        }
    }

    return $installStatus
}

Function Update-StatusLabel {
    param (
        [string]$StatusText
    )

    if ($Global:label3 -eq $null) {
        Write-Warning "StatusLabel is not defined."
        return
    }

    # Invoke on UI Thread if necessary
    $action = {
        $Global:label3.Text = $StatusText
    }

    if ($Global:label3.InvokeRequired) {
        $Global:label3.Invoke($action)
    } else {
        $action.Invoke()
    }
}

Function Setup-GUI {
    param (
        [string]$formTitle,
        [string]$serverHost,
        [System.Collections.ArrayList]$customers,
        [int]$parentCustomerID
    )

    # Load necessary assemblies for Windows Forms
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")

    # Enable visual styles for the form
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Create and configure the form
    $Form1 = New-Object System.Windows.Forms.Form
    $Form1.ClientSize = New-Object System.Drawing.Size(400, 250)
    $Form1.TopMost = $true
    $Form1.Text = $formTitle
    $Form1.StartPosition = "CenterScreen"
    $Form1.SizeGripStyle = "Hide"

    # Add PictureBox control
    $pictureBox = New-Object Windows.Forms.PictureBox
    $pictureBox.Width = 1000
    $pictureBox.Height = 70
    $pictureBox.Location = New-Object System.Drawing.Point(5, 5)
    # TODO: Set the image for pictureBox if required
    $Form1.Controls.Add($pictureBox)

    # Add ComboBox for customer selection
    $comboBox1 = New-Object System.Windows.Forms.ComboBox
    $comboBox1.Location = New-Object System.Drawing.Point(25, 100)
    $comboBox1.Size = New-Object System.Drawing.Size(250, 310)
    # TODO: Configure AutoCompleteMode if needed
    foreach ($Customer in $customers) {
        if ($Customer.ParentID -eq $parentCustomerID) {
            $comboBox1.Items.Add($Customer.Name)
        }
    }
    $Form1.Controls.Add($comboBox1)

    # Add ComboBox for site selection
    $comboBox2 = New-Object System.Windows.Forms.ComboBox
    $comboBox2.Location = New-Object System.Drawing.Point(25, 150)
    $comboBox2.Size = New-Object System.Drawing.Size(250, 310)
    $comboBox1.add_SelectedIndexChanged({
        $comboBox2.Items.Clear()
        $selectedCustomerName = $comboBox1.SelectedItem.ToString()
        $selectedParentID = $customers | Where-Object { $_.Name -eq $selectedCustomerName } | Select-Object -ExpandProperty ID
        $childCustomers = $customers | Where-Object { $_.ParentID -eq $selectedParentID }
        foreach ($child in $childCustomers) {
            $comboBox2.Items.Add($child.Name)
        }
    })
    $Form1.Controls.Add($comboBox2)

    # Add Button control
    $Button = New-Object System.Windows.Forms.Button
    $Button.Location = New-Object System.Drawing.Point(290, 190)
    $Button.Size = New-Object System.Drawing.Size(90, 50)
    $Button.Text = "Install Agent"
    # TODO: Define the Button_Click event handler function
    $Button.Add_Click({ Button_Click })
    $Form1.Controls.Add($Button)

    # Add Label controls
    $labelCustomer = New-Object System.Windows.Forms.Label
    $labelCustomer.Location = New-Object System.Drawing.Point(30, 80)
    $labelCustomer.Size = New-Object System.Drawing.Size(200, 23)
    $labelCustomer.Text = "Select N-Able customer:"
    $Form1.Controls.Add($labelCustomer)

    $labelSite = New-Object System.Windows.Forms.Label
    $labelSite.Location = New-Object System.Drawing.Point(30, 130)
    $labelSite.Size = New-Object System.Drawing.Size(200, 23)
    $labelSite.Text = "Select N-Able site:"
    $Form1.Controls.Add($labelSite)

    $labelStatus = New-Object System.Windows.Forms.Label
    $labelStatus.Location = New-Object System.Drawing.Point(30, 190)
    $labelStatus.Size = New-Object System.Drawing.Size(200, 23)
    $Form1.Controls.Add($labelStatus)

    # Show the form
    $Form1.ShowDialog()
}

# Call the function with the necessary parameters
Setup-GUI -formTitle "NvYA Technology - Install N-Able Agent" -serverHost $serverHost -customers $Global:Customers -parentCustomerID 1332

# Main script execution
$serverHost = "ncod84.n-able.com"
$NWSNameSpace = Get-Namespace
$username = "<USERNAME>"
$password = "<PASSWORD>"

# Get credentials and create a PSCredential object
$creds = Get-CredentialObject -Username $username -Password $password

# Get the customer list from N-Central
$customerList = Get-CustomerList -ServerHost $serverHost -Credentials $creds -Namespace $NWSNameSpace

# Process the customer list and populate the $Customers array
# ... Code to process the customer list ...

# Set up the GUI
Setup-GUI

