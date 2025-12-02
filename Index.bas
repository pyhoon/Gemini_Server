B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=8.8
@EndOfDesignText@
Sub Class_Globals
	Private mreq As ServletRequest
	Private mresp As ServletResponse
End Sub

Public Sub Initialize

End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
	mreq = req
	mresp = resp
    If mreq.RequestURI = "/" Then
        ' Serve the main chat page (index.html, which is in Assets)
        mresp.Write(File.ReadString(Main.srvr.StaticFilesFolder, "index.html"))
    Else
        mresp.SendError(404, "Not Found")
    End If
End Sub