param(
  [Parameter(Mandatory, ParameterSetName = 'Azure')]
  [string]
    $SubscriptionId,
  [Parameter(Mandatory, ParameterSetName = 'Azure')]
  [string]
    $ResourceGroup,
  [Parameter(Mandatory, ParameterSetName = 'Azure')]
  [string]
    $WebappName,
  [Parameter(Mandatory, ParameterSetName = 'Local')]
  [string]
    $InputPath,
  [DateTimeOffset]
  $StartTime = [DateTimeOffset]::Now,
  [DateTimeOffset]
  $EndTime = $StartTime.AddHours(1),
  $OutputPath = "",
  [Switch]
    $ShowGraph
)

# This script is provided as a sample only, no support or guarantees are provided. Run at own risk.

if ($ShowGraph) {
  Add-Type -AssemblyName "System.Windows.Forms.DataVisualization" -ErrorAction "Stop" | Out-Null
}

$diagnosticCategory = "availability"
$detectorName = "tcpopensocketcount"
$data = ""

if ($PSCmdlet.ParameterSetName -eq "Azure") {
  Write-Host "Getting data from Azure for WebApp $WebappName"
  $context = Get-AzureRmContext -ErrorAction "Continue"

  if (!$context -or !$context.Account) {
    Write-Host "Please login to an account with access to subscription Id $SubscriptionId"
    Connect-AzureRmAccount -SubscriptionId $subscriptionId -ErrorAction "Stop" | Out-Null
    $context = Get-AzureRmContext -ErrorAction "Continue"
  }

  if (!$context -or $context.Subscription.Id -ine $SubscriptionId) {
    Write-Host "Switching context to subscription Id $SubscriptionId"
    Set-AzureRmContext -SubscriptionId $SubscriptionId -ErrorAction "Stop" | Out-Null
  } else {
    Write-Host "Using existing context for subscription Id $SubscriptionId"
  }

  Write-Host "Invoking $diagnosticCategory detector $detectorName"
  $data = Invoke-AzureRmResourceAction -ResourceId "/subscriptions/$($SubscriptionId)/resourceGroups/$($ResourceGroup)/providers/Microsoft.Web/sites/$($WebappName)/diagnostics/$($diagnosticCategory)/detectors/$($detectorName)" -Action "execute" -ODataQuery "startTime=$($StartTime.UtcDateTime.ToString('o'))&endTime=$($EndTime.UtcDateTime.ToString('o'))" -ApiVersion "2018-02-01" -Force

  if (!$OutputPath) {
    if (!$OutputPath.EndsWith(".json")) { $OutputPath = "$($OutputPath).json" }
    Write-Host "Writing dump to $OutputPath"
    $data | ConvertTo-Json | Set-Content -Path $OutputPath | Out-Null
  }
} else {
  Write-Host "Reading local file"
  # Todo: Add more checks
  $data = Get-Content -Path $InputPath -ErrorAction "Stop" | ConvertFrom-Json
}

Write-Host "Showing info for detector $($data.detectorDefinition.displayName) [$($data.detectorDefinition.name)]"
Write-Host "Time Range: $($data.startTime) -> $($data.endTime)"
Write-Host "Issue detected: $($data.issueDetected)"
Write-Host "Metric Data:"

if ($ShowGraph) {
  $chart = New-object System.Windows.Forms.DataVisualization.Charting.Chart 
  $chart.Width = 1920
  $chart.Height = 1080
  [void]$chart.Titles.Add("$($data.detectorDefinition.displayName) [$($data.detectorDefinition.name)]")
  $legend = New-Object system.Windows.Forms.DataVisualization.Charting.Legend
  $legend.name = "Legend1"
  $chart.Legends.Add($legend)
  $chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea 
  [void]$chart.ChartAreas.Add($chartArea)
  $colors = @("red","green","blue","black","orange","purple","darkgray")
  $colorIndex = 0
}

foreach ($metric in $data.metrics) {
  Write-Host " > $($metric.name)"

  $metricStats = $metric.values.total | Measure-Object -Minimum -Maximum -Average

  Write-Host " -> Min: $($metricStats.Minimum)"
  Write-Host " -> Avg: $($metricStats.Average)"
  Write-Host " -> Max: $($metricStats.Maximum)"

  Write-Host " -> By Role Instance:"

  foreach ($role in $metric.values | Group-Object -Property roleInstance) {
    Write-Host " --> $($role.Name)"

    $roleStats = $role.Group.total | Measure-Object -Minimum -Maximum -Average

    Write-Host " ---> Min: $($roleStats.Minimum)"
    Write-Host " ---> Avg: $($roleStats.Average)"
    Write-Host " ---> Max: $($roleStats.Maximum)"

    if ($showGraph -and $chart)
    {
      $title = "$($metric.name) - $($role.Name)"
      [void]$chart.Series.Add($title)
      $values | fl
      [void]$chart.Series[$title].Points.DataBindXY($role.Group.timestamp, $role.Group.total)
      $chart.Series[$title].ChartType = "Line"
      $chart.Series[$title].IsVisibleInLegend = $true
      $chart.Series[$title].BorderWidth  = 3
      $chart.Series[$title].Legend = "Legend1"
      $chart.Series[$title].color = $colors[$colorIndex % $colors.Length]
      $colorIndex++
    }
  }
}

if ($ShowGraph -and $chart) {
  $graphPath = ".\$([Guid]::NewGuid()).png";
  Write-Host "Opening Graph image $graphPath"
  $chart.SaveImage($graphPath,"png") | Out-Null
  & $graphPath
}

