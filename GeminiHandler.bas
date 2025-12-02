B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=10.3
@EndOfDesignText@
Sub Class_Globals
	Private NewLine As String = (Chr(13) & Chr(10)).As(String)
End Sub

Public Sub Initialize
    
End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
    HandleGemini(req, resp)
	'StartMessageLoop
End Sub

Sub HandleGemini (req As ServletRequest, resp As ServletResponse)
	Log("GeminiHandler started")
    
	' Set headers for Server-Sent Events
	resp.ContentType = "text/event-stream; charset=utf-8"
	'resp.SetHeader("User-Agent", Main.USER_AGENT)
	resp.SetHeader("Cache-Control", "no-cache")
	resp.SetHeader("Connection", "keep-alive")
	resp.SetHeader("Access-Control-Allow-Origin", "*")
    
	Try
		' Get the data parameter
		Dim dataParam As String = req.GetParameter("data")
		If dataParam = "" Then
			SendError(resp, "Missing data parameter")
			Return
		End If
        
		' Parse the JSON data
		Dim json As JSONParser
		json.Initialize(dataParam)
		Dim data As Map = json.NextObject
		Dim prompt As String = data.Get("prompt")
        
		If prompt = "" Or prompt = "null" Then
			SendError(resp, "Missing or invalid prompt")
			Return
		End If
		LogColor("Processing prompt: " & prompt, -16776961)

		Main.API_URL = $"https://generativelanguage.googleapis.com/v1beta/models/${Main.GEMINI_MODEL}:streamGenerateContent"$ & "?key=" & Main.GEMINI_API_KEY
		LogColor(Main.API_URL, -16776961)
		
		' Create Gemini request
		'Dim geminiReq As Map = CreateMap( _
		'    "contents": Array(CreateMap( _
		'        "parts": Array(CreateMap( _
		'            "text": prompt _
		'        )) _
		'    )), _
		'    "generationConfig": CreateMap( _
		'        "maxOutputTokens": 1024, _
		'        "temperature": 0.7 _
		'    ) _
		')
		Dim geminiReq As Map = CreateMap( _
		            "contents": Array(CreateMap( _
		                "parts": Array(CreateMap( _
		                    "text": prompt _
		                )) _
		            )))
			
		Dim requestJson As String = geminiReq.As(JSON).ToString
		Log("Sending streaming request to Gemini API")
		
		' Make HTTP request to Gemini
		Dim j As HttpJob
		j.Initialize("gemini", Me)
		j.PostString(Main.API_URL, requestJson)
		j.GetRequest.SetContentType("application/json")
		'j.GetRequest.SetHeader("x-goog-api-key", Main.GEMINI_API_KEY)
		
		Wait For (j) JobDone(j As HttpJob)
		If j.Success Then
			Dim response As String = j.GetString
			LogColor(response, -16776961)
			Log("Gemini API call successful, response length: " & response.Length)
			
			If response = "" Or response = "null" Then
				SendError(resp, "Empty response from Gemini")
				Return
			End If
			
			' Check for API errors first
			If response.IndexOf($"${QUOTE}error${QUOTE}"$) > -1 Then
				Dim errorMap As Map = response.As(JSON).ToMap
				If errorMap.ContainsKey("error") Then
					Dim errorObj As Map = errorMap.Get("error")
					Dim errorMsg As String = errorObj.GetDefault("message", "Unknown API error")
					SendError(resp, "Gemini API: " & errorMsg)
					Return
				Else
					LogColor(errorMap.As(JSON).ToString, -65536)
				End If
			End If
		
			If response.StartsWith("[") Then
				Dim responses As List = response.As(JSON).ToList
				For Each item As Map In responses
					If item.ContainsKey("candidates") Then
						Dim candidates As List = item.Get("candidates")
						ProcessCandidates(resp, candidates)
					End If
				Next
				'ProcessAndStreamResponseAsList(response, resp)
			Else
				Dim item As Map = response.As(JSON).ToMap
				If item.ContainsKey("candidates") Then
					Dim candidates As List = item.Get("candidates")
					ProcessCandidates(resp, candidates)
				End If
				'ProcessAndStreamResponseAsMap(response, resp)
			End If
			' Send completion signal
			SendChunk(resp, "[DONE]")
			'LogColor("Response streaming completed. Total text length: " & fullText.Length, -16776961)
		Else
			LogColor("Gemini API error: " & j.ErrorMessage, -65536)
			SendError(resp, "API Error: " & j.ErrorMessage)
		End If
	Catch
		LogColor("Error in GeminiHandler: " & LastException.Message, -65536)
		Try
			SendError(resp, "Server error: " & LastException.Message)
		Catch
			' Ignore if client already disconnected
			LogColor(LastException.Message, -65536)
		End Try
	End Try
	j.Release
	'StopMessageLoop
End Sub

Sub ProcessCandidates (resp As ServletResponse, candidates As List)
	If candidates.Size > 0 Then
		Dim fullText As StringBuilder
		fullText.Initialize
		Dim candidate As Map = candidates.Get(0)
		If candidate.ContainsKey("content") Then
			Dim content As Map = candidate.Get("content")
			If content.ContainsKey("parts") Then
				Dim parts As List = content.Get("parts")
				For Each part As Map In parts
					If part.ContainsKey("text") Then
						Dim text As String = part.Get("text")
						Log(text)
						If text <> "" And text <> "null" Then
							fullText.Append(text)
							' Send chunk immediately
							SendChunk(resp, text)
						End If
					End If
				Next
			End If
			LogColor("Response streaming completed. Total text length: " & fullText.Length, -16776961)
		End If
	End If
End Sub

Sub SendChunk (resp As ServletResponse, content As String)
	Try
		' Build proper SSE with event type
		Dim sseBuilder As StringBuilder
		sseBuilder.Initialize
        
		' Add event type
		If content = "[DONE]" Then
			sseBuilder.Append("event: ").Append("complete").Append(NewLine)
			Dim data As Map = CreateMap("status": "complete")
		Else
			sseBuilder.Append("event: ").Append("message").Append(NewLine)
			Dim data As Map = CreateMap("content": content)
		End If
        
		' Add data
		sseBuilder.Append("data: ").Append(data.As(JSON).ToCompactString).Append(NewLine)
        
		' End of event
		sseBuilder.Append(NewLine)
        
		Dim sseData As String = sseBuilder.ToString
		'Dim bytes() As Byte = sseData.GetBytes("UTF8")
        
		' DEBUG: Log what we're sending
		'LogColor("SSE Event - Type: " & eventType & ", Data: " & jsonGen.ToString, Colors.Magenta)
        
		'out.WriteBytes(bytes, 0, bytes.Length)
		'out.Flush
		
		'If content = "[DONE]" Then
		'	Dim data As Map = CreateMap("status": "complete")
		'Else
		'	Dim data As Map = CreateMap("content": content)
		'End If

		'Dim sseData As String = "data: " & data.As(JSON).ToString & NewLine & NewLine

		Log(sseData)
		resp.Write(sseData)
		'resp.OutputStream.Flush
	Catch
		If LastException.Message.Contains("EofException") Or LastException.Message.Contains("Closed") Then
			Log("Client disconnected during streaming")
		Else
			Log("Error sending chunk: " & LastException.Message)
		End If
	End Try
End Sub

Sub SendError (resp As ServletResponse, errorMessage As String)
    Try
        LogColor("Sending error: " & errorMessage, -65536)
		
		' Build proper SSE with event type
		Dim sseBuilder As StringBuilder
		sseBuilder.Initialize
        
		' Add event type
		sseBuilder.Append("event: ").Append("error").Append(NewLine)

		' Add data
		Dim errorData As Map = CreateMap("error": errorMessage)
		sseBuilder.Append("data: ").Append(errorData.As(JSON).ToCompactString).Append(NewLine)
        
		' End of event
		sseBuilder.Append(NewLine)
		
		Dim sseError As String = sseBuilder.ToString
        'Dim sseError As String = "data: " & errorData.As(JSON).ToString & NewLine & NewLine
        'Dim sseError As String = "data: " & errorData.As(JSON).ToString & NewLine & NewLine
        resp.Write(sseError)
        'resp.OutputStream.Flush
    Catch
        LogColor("Error sending error message: " & LastException.Message, -65536)
    End Try
End Sub