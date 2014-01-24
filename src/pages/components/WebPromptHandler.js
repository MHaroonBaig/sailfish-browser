/****************************************************************************
**
** Copyright (C) 2014 Jolla Ltd.
** Contact: Raine Makelainen <raine.makelainen@jolla.com>
**
****************************************************************************/

.pragma library

var pageStack
var activeWebView
var prompts

function openAlert(data) {
    var winid = data.winid
    var dialog = pageStack.push(prompts.alertComponentUrl,
                                {"text": data.text})
    // TODO: also the Async message must be sent when window gets closed
    dialog.done.connect(function() {
        activeWebView.sendAsyncMessage("alertresponse", {"winid": winid})
    })
}

function openConfirm(data) {
    var winid = data.winid
    var dialog = pageStack.push(prompts.confirmComponentUrl,
                                {"text": data.text})
    // TODO: also the Async message must be sent when window gets closed
    dialog.accepted.connect(function() {
        activeWebView.sendAsyncMessage("confirmresponse",
                         {"winid": winid, "accepted": true})
    })
    dialog.rejected.connect(function() {
        activeWebView.sendAsyncMessage("confirmresponse",
                         {"winid": winid, "accepted": false})
    })
}

function openPrompt(data) {
    var winid = data.winid
    var dialog = pageStack.push(prompts.queryComponentUrl,
                                {"text": data.text, "value": data.defaultValue})
    // TODO: also the Async message must be sent when window gets closed
    dialog.accepted.connect(function() {
        activeWebView.sendAsyncMessage("promptresponse",
                         {
                             "winid": winid,
                             "accepted": true,
                             "promptvalue": dialog.value
                         })
    })
    dialog.rejected.connect(function() {
        activeWebView.sendAsyncMessage("promptresponse",
                         {"winid": winid, "accepted": false})
    })
}
