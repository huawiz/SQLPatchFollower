# SQL Server 更新通知腳本
# 用途：監控SQL Server更新並通過Line發送通知
# 作者：Justin
# 最後更新：2025/01/17

#region 函數定義
function New-SQLUpdateNotification {
    <#
    .SYNOPSIS
        建立SQL Server更新的Line通知訊息
    .DESCRIPTION
        根據提供的SQL Server更新信息，生成用於Line Messaging API的Flex Message格式通知
    .PARAMETER SQLVersion
        SQL Server的版本號
    .PARAMETER KBNumber
        知識庫(KB)編號
    .PARAMETER PatchName
        更新補丁名稱
    .PARAMETER ReleaseTime
        發布時間
    .PARAMETER UpdateLink
        更新的下載連結，預設為Line官網
    .EXAMPLE
        New-SQLUpdateNotification -SQLVersion "SQL2019" -KBNumber "KB5029666" -PatchName "CU22" -ReleaseTime "2024/01/17"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SQLVersion,
        
        [Parameter(Mandatory = $true)]
        [string]$KBNumber,
        
        [Parameter(Mandatory = $true)]
        [string]$PatchName,
        
        [Parameter(Mandatory = $true)]
        [string]$ReleaseTime,
        
        [Parameter(Mandatory = $false)]
        [string]$UpdateLink = "https://line.me/"
    )
    
    # 建立Line Flex Message結構
    $notification = @{
        type = "bubble"
        body = @{
            type = "box"
            layout = "vertical"
            contents = @(
                # 標題區塊
                @{
                    type = "text"
                    text = "發現新的SQL更新"
                    weight = "bold"
                    size = "xl"
                },
                # 內容區塊
                @{
                    type = "box"
                    layout = "vertical"
                    margin = "lg"
                    spacing = "sm"
                    contents = @(
                        # SQL版本資訊
                        @{
                            type = "box"
                            layout = "baseline"
                            spacing = "sm"
                            contents = @(
                                @{
                                    type = "text"
                                    text = "SQL版本"
                                    color = "#aaaaaa"
                                    size = "sm"
                                    flex = 2
                                    wrap = $true
                                },
                                @{
                                    type = "text"
                                    text = $SQLVersion
                                    wrap = $true
                                    color = "#666666"
                                    size = "sm"
                                    flex = 4
                                }
                            )
                        },
                        # KB編號資訊
                        @{
                            type = "box"
                            layout = "baseline"
                            spacing = "sm"
                            contents = @(
                                @{
                                    type = "text"
                                    text = "KB編號"
                                    color = "#aaaaaa"
                                    size = "sm"
                                    flex = 2
                                    wrap = $true
                                },
                                @{
                                    type = "text"
                                    text = $KBNumber
                                    wrap = $true
                                    color = "#666666"
                                    size = "sm"
                                    flex = 4
                                }
                            )
                        },
                        # 更新版號資訊
                        @{
                            type = "box"
                            layout = "baseline"
                            spacing = "sm"
                            contents = @(
                                @{
                                    type = "text"
                                    text = "更新版號"
                                    color = "#aaaaaa"
                                    size = "sm"
                                    flex = 2
                                    wrap = $true
                                },
                                @{
                                    type = "text"
                                    text = $PatchName
                                    wrap = $true
                                    color = "#666666"
                                    size = "sm"
                                    flex = 4
                                }
                            )
                        },
                        # 發布日期資訊
                        @{
                            type = "box"
                            layout = "baseline"
                            spacing = "sm"
                            contents = @(
                                @{
                                    type = "text"
                                    text = "推出日期"
                                    color = "#aaaaaa"
                                    size = "sm"
                                    flex = 2
                                },
                                @{
                                    type = "text"
                                    text = $ReleaseTime
                                    wrap = $true
                                    color = "#666666"
                                    size = "sm"
                                    flex = 4
                                }
                            )
                        }
                    )
                }
            )
        }
        # 底部按鈕區塊
        footer = @{
            type = "box"
            layout = "vertical"
            spacing = "sm"
            contents = @(
                @{
                    type = "button"
                    style = "primary"
                    height = "sm"
                    action = @{
                        type = "uri"
                        label = "查看更新"
                        uri = $UpdateLink
                    }
                },
                @{
                    type = "box"
                    layout = "vertical"
                    contents = @()
                    margin = "sm"
                }
            )
            flex = 0
        }
    }
    
    return $notification | ConvertTo-Json -Depth 10
}
#endregion

#region 主要執行邏輯
# 設定基本變數
$Path = Split-Path $MyInvocation.MyCommand.Path  # 獲取腳本所在目錄
$Log = Join-Path $Path 'PatchLog.log'           # 日誌文件路徑
$LogDate = Get-Date -Format "yyyy/MM/dd HH:mm"     # 當前時間

# 獲取最新和次新的CSV文件
$Newest = Get-ChildItem $Path/*.csv | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Second = Get-ChildItem $Path/*.csv | Sort-Object LastWriteTime -Descending | Select-Object -Skip 1 -First 1

# Line Messaging API 設定
$token = $env:LINE_BOT_TOKEN

# 比較新舊文件內容
if (Compare-Object (Get-Content $Newest) (Get-Content $Second)) {
    # 獲取新增和移除的內容
    $New_Detail = Compare-Object (Get-Content $Newest) (Get-Content $Second) | 
                 Where-Object { $_.SideIndicator -eq '<=' } | 
                 Select-Object -ExpandProperty InputObject
    
    $Old_Detail = Compare-Object (Get-Content $Newest) (Get-Content $Second) | 
                 Where-Object { $_.SideIndicator -eq '=>' } | 
                 Select-Object -ExpandProperty InputObject
    
    # 處理每個新增的更新
    foreach ($x in $New_Detail) {
        # 清理CSV數據
        $cleanData = $x.Replace('"', '').Split(',')
        
        # 建立版本信息hashtable
        $version_info = @{
            SQLVersion  = $cleanData[0]
            KBNumber    = $cleanData[1]
            ReleaseTime = $cleanData[2]    
            PatchName   = $cleanData[3]
            UpdateLink  = $cleanData[4]
        }

        # 生成更新通知
        $updateInfo = New-SQLUpdateNotification @version_info

        # 設定Line API請求標頭
        $headers = @{
            'Content-Type'      = 'application/json'
            'Authorization'     = "Bearer $token"
            'X-Line-Retry-Key' = [guid]::NewGuid().ToString()
        }
    
        # 準備請求內容
        $body = @{
            messages = @(
                @{
                    type     = "flex"
                    altText  = "SQL Server Patch 更新通知"
                    contents = $updateInfo | ConvertFrom-Json
                }
            )
            notificationDisabled = $true    # 注意這裡是用 $true，不是字串 "true"
        } | ConvertTo-Json -Depth 10
        
        # 轉換為UTF8編碼
        $body = [System.Text.Encoding]::UTF8.GetBytes($body)
    
        # 發送Line通知
        try {
            #Invoke-RestMethod  -Uri 'https://api.line.me/v2/bot/message/broadcast' -Method Post -Headers $headers -Body $body
        }
        catch {
            Write-Output "$LogDate 發送Line通知失敗: $($_.Exception.Message)" | Out-File -FilePath $Log -Encoding UTF8 -Append
        }
        # 記錄更新日誌
        Write-Output "$LogDate 版本不一致，New:$($version_info.Values -join ',' )" | Out-File -FilePath $Log -Encoding UTF8 -Append
    }

    
    
}
else {
    # 記錄無更新日誌
    Write-Output "$LogDate 版本一致" | Out-File -FilePath $Log -Encoding UTF8 -Append
}
