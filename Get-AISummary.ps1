# 設定 Azure OpenAI API 參數
$apiKey = $env:AZ_OPENAI_API_KEY
$endpoint = "https://sqlpatch-ai.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-02-15-preview"

function Get-FirstTableContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url
    )
    
    try {
        Write-Verbose "設定 TLS 1.2"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        Write-Verbose "初始化 WebClient"
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        
        Write-Verbose "下載網頁內容"
        $htmlContent = $webClient.DownloadString($Url)
        
        Write-Verbose "開始解析第一個表格內容"
        $tablePattern = '<table.*?>(.*?)</table>'
        $tableMatch = [regex]::Match($htmlContent, $tablePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        
        if (-not $tableMatch.Success) {
            Write-Warning "未找到表格內容"
            return $null
        }
        
        $tableContent = $tableMatch.Groups[1].Value
        
        # 解析表格行
        $rowPattern = '<tr.*?>(.*?)</tr>'
        $rows = [regex]::Matches($tableContent, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        
        # 創建結果陣列
        $tableData = @()
        
        foreach ($row in $rows) {
            # 解析單元格
            $cellPattern = '<td.*?>(.*?)</td>'
            $cells = [regex]::Matches($row.Groups[1].Value, $cellPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
            
            if ($cells.Count -gt 0) {
                $rowData = $cells | ForEach-Object {
                    # 清理 HTML 標籤和多餘空白
                    $cellContent = $_.Groups[1].Value
                    $cellContent = $cellContent -replace '<[^>]+>', ' '
                    $cellContent = $cellContent -replace '&nbsp;', ' '
                    $cellContent = ($cellContent -replace '\s+', ' ').Trim()
                    $cellContent
                }
                $tableData += , $rowData
            }
        }
        
        return $tableData
    }
    catch {
        Write-Error "處理網頁內容時發生錯誤: $_"
        return $null
    }
}
function Invoke-WebRequestWithEncoding {
    param (
        [string]$Uri,
        [string]$Method = "Post",
        [hashtable]$Headers,
        [string]$Body
    )
    
    try {
        # 建立 WebRequest 物件
        $request = [System.Net.WebRequest]::Create($Uri)
        $request.Method = $Method
        $request.ContentType = "application/json; charset=utf-8"
        
        # 加入標頭
        foreach ($header in $Headers.GetEnumerator()) {
            $request.Headers[$header.Key] = $header.Value
        }
        
        # 寫入請求內容
        if ($Body) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $request.ContentLength = $bytes.Length
            
            $stream = $request.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
        }
        
        # 獲取回應
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $result = $reader.ReadToEnd()
        
        $reader.Close()
        $response.Close()
        
        return $result | ConvertFrom-Json
    }
    catch {
        Write-Error "API 請求失敗: $_"
        throw
    }
}

function Invoke-AzureOpenAIAnalysis {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [array]$TableData
    )
    
    # 準備結構化內容
    $structuredContent = "SQL Server 更新資訊：`n"
    foreach ($row in $TableData) {
        $structuredContent += "`n問題狀況："
        $structuredContent += "`n$($row[0])"
        if ($row.Count -gt 1) {
            $structuredContent += "`n解決方案："
            $structuredContent += "`n$($row[1])"
        }
        $structuredContent += "`n---"
    }
    
    # 準備請求內容
    $messages = @(
        @{
            role = "system"
            content = @(
                @{
                    type = "text"
                    text = "請依照以下結構，用一句繁體中文說明此次 SQL Server 更新：

第一句：主要針對哪些SQL Server功能做更新。

請用口語化的方式表達，避免技術術語，讓一般 DBA 容易理解。"
                }
            )
        }
        @{
            role = "user"
            content = @(
                @{
                    type = "text"
                    text = $structuredContent
                }
            )
        }
    )
    
    $body = @{
        messages = $messages
        temperature = 0.3
        top_p = 0.95
        max_tokens = 800
    } | ConvertTo-Json -Depth 10 -Compress
    
    try {
        Write-Verbose "發送請求到 Azure OpenAI API"
        $headers = @{
            "api-key" = $apiKey
        }
        
        $response = Invoke-WebRequestWithEncoding `
            -Uri $endpoint `
            -Method "Post" `
            -Headers $headers `
            -Body $body
        
        if ($response.choices) {
            return $response.choices[0].message.content
        }
        else {
            Write-Error "API 回應中沒有找到有效內容"
            return $null
        }
    }
    catch {
        Write-Error "呼叫 Azure OpenAI API 時發生錯誤: $_"
        return $null
    }
}

function Analyze-SQLServerUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url
    )
    
    Write-Host "開始分析 SQL Server 更新內容..."
    
    # 獲取表格內容
    $tableData = Get-FirstTableContent -Url $Url -Verbose:$VerbosePreference
    
    if ($tableData) {
        Write-Host "`n正在使用 Azure OpenAI 分析更新內容..."
        $analysis = Invoke-AzureOpenAIAnalysis -TableData $tableData
        
        if ($analysis) {
            Write-Host "`nAI 分析結果："
            Write-Host $analysis
            
            # 保存分析結果
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $outputFile = "SQLServer_Update_Analysis_$timestamp.txt"
            $analysis | Out-File -FilePath $outputFile -Encoding UTF8
            Write-Host "`n分析結果已保存到文件：$outputFile"
        }
    }
}

# 使用範例（加入 -Verbose 參數以查看詳細診斷資訊）
$url = "https://learn.microsoft.com/zh-tw/troubleshoot/sql/releases/sqlserver-2022/cumulativeupdate17"
Analyze-SQLServerUpdate -Url $url -Verbose
