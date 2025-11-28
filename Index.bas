B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=8.8
@EndOfDesignText@
'Handler class
Sub Class_Globals
	Private mreq As ServletRequest 'ignore
	Private mresp As ServletResponse 'ignore
End Sub

Public Sub Initialize
	
End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
	mreq = req
	mresp = resp

	If mreq.RequestURI = "/" Then
		Dim Content As String = File.ReadString(File.DirAssets, "index.html")
		'Content = Content.Replace("$PARAMS$", Main.PrintAllParameters(mreq))
	
		mresp.ContentType = "text/html"
		mresp.Write(Content)
		'mresp.OutputStream.Close
	Else If mreq.RequestURI.StartsWith("/gemini") Then
		generate
	End If
End Sub

Sub generate
    ' 1. Get the Prompt from the client request
    Dim Prompt As String = mreq.GetParameter("prompt")
    If Prompt = "" Then Prompt = "Write a long poem about coding in B4J."
    
    ' 2. Set response type to event-stream (Standard for SSE)
    mresp.ContentType = "text/event-stream"
    mresp.CharacterEncoding = "UTF-8"
    
    ' 3. Call the streamer
    Dim jo As JavaObject = Me
    'JO.InitializeNewInstance(Me, Null)
    
    ' This Java method will block this thread until the stream is done, 
    ' writing chunks directly to the resp.OutputStream
    jo.RunMethod("StreamToClient", Array(Main.GeminiApiKey, Prompt, mresp))
End Sub

#If JAVA
import okhttp3.*;
import java.io.*;
//import javax.servlet.ServletResponse;
import jakarta.servlet.ServletResponse;
import org.json.JSONObject; // B4J usually includes org.json or similar, if not use simple string manipulation

public void StreamToClient(String apiKey, String prompt, ServletResponse resp) {
    try {
        // A. Setup the Client
        OkHttpClient client = new OkHttpClient();
        
        // B. Construct JSON Payload
        // Manual string construction is faster/easier here than importing complex JSON libs
        String jsonBody = "{ \"contents\": [{ \"parts\": [{ \"text\": \"" + prompt.replace("\"", "\\\"") + "\" }] }] }";
        
        MediaType JSON = MediaType.get("application/json; charset=utf-8");
        RequestBody body = RequestBody.create(jsonBody, JSON);

        // C. Build Request with alt=sse
        Request request = new Request.Builder()
            .url("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse&key=" + apiKey)
            .post(body)
            .build();

        // D. Execute and Read Stream
        try (Response response = client.newCall(request).execute()) {
            if (!response.isSuccessful()) {
                 resp.getWriter().write("data: Error: " + response.code() + "\n\n");
                 return;
            }

            // Read line by line
            BufferedReader reader = new BufferedReader(new InputStreamReader(response.body().byteStream()));
            String line;
            
            while ((line = reader.readLine()) != null) {
                // Gemini sends lines starting with "data: "
                if (line.startsWith("data: ")) {
                    String jsonPart = line.substring(6).trim();
                    
                    // "data: [DONE]" is the end signal
                    if (jsonPart.equals("[DONE]")) break;
                    
                    try {
                        // Minimal parsing to extract text
                        // We rely on standard string manipulation to avoid dependency hell
                        // Target structure: candidates[0].content.parts[0].text
                        
                        int textIndex = jsonPart.indexOf("\"text\": \"");
                        if (textIndex > -1) {
                            int start = textIndex + 9; // length of "text": "
                            // Find the closing quote, keeping in mind escaped quotes might exist
                            // For simplicity in this example, we assume standard JSON flow. 
                            // For production, use a proper JSON parser like org.json.JSONObject
                            
                            // Let's use B4J's internal JSON parser logic via simple string split for robustness
                            // Or simpler: pass the raw JSON chunk to the client and let the client parse it!
                            
                            // OPTION 1: Forward the Raw JSON to client (Easiest)
                            resp.getOutputStream().write(("data: " + jsonPart + "\n\n").getBytes("UTF-8"));
                            resp.getOutputStream().flush();
                        }
                    } catch (Exception e) {
                        // ignore parse errors for empty lines
                    }
                }
            }
        }
    } catch (Exception e) {
        e.printStackTrace();
    }
}
#End If