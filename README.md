# SQLPatch-AI-Notifier 

自動追蹤 SQL Server 的補丁更新，利用AZURE OPENAI統整複雜的更新資訊，並透過 Line Bot 即時推送到你的手機。

## ETL

1. Extract : 

從微軟網站獲取補丁資訊(EXCEL FILE)

定期抓取微軟官方最新的Patch資訊更新文件，在檔名標註時間、保留最大檔案數為2

2. Transform
    
    a. 比較新舊EXCEL資料、輸出成可用格式
    b. 若比較發現資料有更新，將更新內容餵給AZURE OPENAI，取得統整資訊


3. Load (資料裝載/發送)

    將資訊套入Line api模板(json)，透過Chatbot發送資料


---

## 範例圖
![](/img/Linebot.png)