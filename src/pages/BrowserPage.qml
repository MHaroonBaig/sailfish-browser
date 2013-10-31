/****************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Vesa-Matti Hartikainen <vesa-matti.hartikainen@jollamobile.com>
**
****************************************************************************/


import QtQuick 2.0
import Sailfish.Silica 1.0
import Qt5Mozilla 1.0
import Sailfish.Browser 1.0
import MeeGo.Connman 0.2
import "components" as Browser


Page {
    id: browserPage

    property alias tabs: tabModel
    property alias favorites: favoriteModel
    property alias history: historyModel
    property alias currentTabIndex: tabModel.currentTabIndex
    property alias viewLoading: webView.loading
    property alias currentTab: tab
    property string title
    property string url

    // Move this inside WebContainer
    readonly property bool fullscreenMode: (webView.chromeGestureEnabled && !webView.chrome) || webContainer.inputPanelVisible || !webContainer.foreground

    property string favicon
    property Item _contextMenu
    property bool _ctxMenuActive: _contextMenu != null && _contextMenu.active
    // As QML can't disconnect closure from a signal (but methods only)
    // let's keep auth data in this auxilary attribute whose sole purpose is to
    // pass arguments to openAuthDialog().
    property variant _authData: null

    // Used by newTab function
    property bool newTabRequested

    function newTab(link, foreground, title) {
        if (foreground) {
            if (webView.loading) {
                webView.stop()
            }
            tab.loadWhenTabChanges = true
        }
        // tabMovel.addTab does not trigger anymore navigateTo call. Always done via
        // QmlMozView onUrlChanged handler.
        // Loading newTabs seems to be broken. When an url that was already loaded is loaded again and still
        // active in one of the tabs, the tab containing the url is not brought to foreground.
        // This was broken already before this change. We need to add mapping between intented
        // load url and actual result url to TabModel::activateTab so that finding can be done.
        tabModel.addTab(link, foreground)
        load(link, title)
    }

    function closeTab(index) {
        if (tabModel.count == 0) {
            return
        }

        tab.loadWhenTabChanges = true

        if (index == currentTabIndex && webView.loading) {
            webView.stop()
        }

        tabModel.remove(index)
    }

    function load(url, title) {
        if (tabModel.count == 0) {
            newTab(url, true)
        }

        if (title) {
            browserPage.title = title
        } else {
            browserPage.title = ""
        }

        // Always enable chrome when load is called.
        webView.chrome = true
        if (url !== "" && webView.url != url) {
            // We clear the old thumbnail when on foreground
            // so that incase user tabs thumbs page before firstPaint we are not showing wrong thumb
            if (webContainer.pageActive && tab.thumbnailPath!="") {
                WebUtils.deleteThumbnail(tab.thumbnailPath)
            }
            browserPage.url = url
            resourceController.firstFrameRendered = false
            if (networkManager.state !== "online" && networkManager.state !== "ready") {
                networkManager.reloadNeeded = true
            }
            webView.load(url)
        }
    }

    function loadTab(index, url, title) {
        if (webView.loading) {
            webView.stop()
        }

        if (url) {
            browserPage.url = url
        }

        if (title) {
            browserPage.title = title
        }
        tab.loadWhenTabChanges = true;
        currentTabIndex = index
    }

    function deleteTabHistory() {
        historyModel.clear()
    }

    function captureScreen() {
        if (status == PageStatus.Active && resourceController.firstFrameRendered) {
            tab.captureScreen(webView.url, 0, 0, webView.width,
                              webView.width, window.screenRotation)
        }
    }

    function closeAllTabs() {
        tabModel.clear()
    }

    function openAuthDialog(input) {
        var data = input !== undefined ? input : browserPage._authData
        var winid = data.winid

        if (browserPage._authData !== null) {
            auxTimer.triggered.disconnect(browserPage.openAuthDialog)
            browserPage._authData = null
        }

        var dialog = pageStack.push(Qt.resolvedUrl("components/AuthDialog.qml"),
                                    {
                                        "hostname": data.text,
                                        "realm": data.title,
                                        "username": data.defaultValue,
                                        "passwordOnly": data.passwordOnly
                                    })
        dialog.accepted.connect(function () {
            webView.sendAsyncMessage("authresponse",
                                       {
                                           "winid": winid,
                                           "accepted": true,
                                           "username": dialog.username,
                                           "password": dialog.password
                                       })
        })
        dialog.rejected.connect(function() {
            webView.sendAsyncMessage("authresponse",
                                       {"winid": winid, "accepted": false})
        })
    }

    function openContextMenu(linkHref, imageSrc, linkTitle, contentType) {
        var ctxMenuComp

        if (_contextMenu) {
            _contextMenu.linkHref = linkHref
            _contextMenu.linkTitle = linkTitle.trim()
            _contextMenu.imageSrc = imageSrc
            hideVirtualKeyboard()
            _contextMenu.show()
        } else {
            ctxMenuComp = Qt.createComponent(Qt.resolvedUrl("components/BrowserContextMenu.qml"))
            if (ctxMenuComp.status !== Component.Error) {
                _contextMenu = ctxMenuComp.createObject(browserPage,
                                                        {
                                                            "linkHref": linkHref,
                                                            "imageSrc": imageSrc,
                                                            "linkTitle": linkTitle.trim(),
                                                            "contentType": contentType
                                                        })
                hideVirtualKeyboard()
                _contextMenu.show()
            } else {
                console.log("Can't load BrowserContextMenu.qml")
            }
        }
    }

    function hideVirtualKeyboard() {
        if (Qt.inputMethod.visible) {
            browserPage.focus = true
        }
    }

    // Safety clipping. There is clipping in ApplicationWindow that should react upon focus changes.
    // This clipping can handle also clipping of QmlMozView. When this page is active we do not need to clip
    // if input method is not visible.
    clip: status != PageStatus.Active || webContainer.inputPanelVisible

    TabModel {
        id: tabModel
    }

    HistoryModel {
        id: historyModel

        tabId: tabModel.currentTabId
    }

    Tab {
        id: tab

        // Indicates whether the next url that is set to this Tab element will be loaded.
        // Used when new tabs are created, tabs are loaded, and with back and forward,
        // All of these actions load data asynchronously from the DB, and the changes
        // are reflected in the Tab element.
        property bool loadWhenTabChanges: false
        property bool backForwardNavigation: false

        tabId: tabModel.currentTabId

        onUrlChanged: {
            if (tab.valid && (loadWhenTabChanges || backForwardNavigation)) {
                // Both url and title are updated before url changed is emitted.
                load(url, title)
                // loadWhenTabChanges will be set to false when mozview says that url has changed
                // loadWhenTabChanges = false
            }
        }
    }

    Browser.DownloadRemorsePopup { id: downloadPopup }

    // TODO: Merge webContainer and QmlMozView into Sailfish Browser WebView.
    // It should contain all function defined at BrowserPage. BrowserPage
    // should only have call through function when needed e.g. by TabPage.
    // It should also handle title, url, forwardNavigation, backwardNavigation.
    // In addition, it should be fixed to fullscreen size and internally
    // it changes height for QmlMozView.
    WebContainer {
        id: webContainer

        width: parent.width
        // We have currently orientation locked. Need to be tested when landscape enabled.
        height: browserPage.orientation === Orientation.Portrait ? Screen.height : Screen.width
        pageActive: browserPage.status == PageStatus.Active
        webView: webView

        foreground: Qt.application.active
        inputPanelHeight: window.pageStack.panelSize
        inputPanelOpenHeight: window.pageStack.imSize
        toolbarHeight: toolBarContainer.height

        Rectangle {
            id: background
            anchors.fill: parent
            color: webView.bgcolor ? webView.bgcolor : "white"
        }
    }

    Browser.ResourceController {
        id: resourceController
        webView: webView
        background: webContainer.background
    }

    QmlMozView {
        id: webView

        readonly property bool loaded: loadProgress === 100
        property bool userHasDraggedWhileLoading

        enabled: browserPage.status == PageStatus.Active
        // There needs to be enough content for enabling chrome gesture
        chromeGestureThreshold: toolBarContainer.height
        chromeGestureEnabled: contentHeight > webContainer.height + chromeGestureThreshold

        signal selectionRangeUpdated(variant data)
        signal selectionCopied(variant data)
        signal contextMenuRequested(variant data)

        focus: true
        width: browserPage.width
        state: ""

        //{ // TODO
        // No resizes while page is not active
        // also contextmenu size
        //           if (browserPage.status == PageStatus.Active) {
        //               return (_contextMenu != null && (_contextMenu.height > tools.height)) ? browserPage.height - _contextMenu.height : browserPage.height - tools.height
        //               return (_contextMenu != null && (_contextMenu.height > tools.height)) ? 200 : 300

        // Order of onTitleChanged and onUrlChanged is unknown. Hence, use always browserPage.title and browserPage.url
        // as they are set in the load function of BrowserPage.
        onTitleChanged: {
            // This is always after url has changed
            browserPage.title = title
            tab.updateTab(browserPage.url, browserPage.title, "")
        }

        onUrlChanged: {
            browserPage.url = url
            if (tab.backForwardNavigation) {
                tab.updateTab(browserPage.url, browserPage.title, "")
                tab.backForwardNavigation = false
            } else if (!browserPage.newTabRequested) {
                // Use browserPage.title here to avoid wrong title to blink.
                // browserPage.load() updates browserPage's title before load starts.
                // QmlMozView's title is not correct over here.
                tab.navigateTo(browserPage.url, browserPage.title, "")
            }
            tab.loadWhenTabChanges = false
            browserPage.newTabRequested = false
        }

        onBgcolorChanged: {
            var bgLightness = WebUtils.getLightness(bgcolor)
            var dimmerLightness = WebUtils.getLightness(Theme.highlightDimmerColor)
            var highBgLightness = WebUtils.getLightness(Theme.highlightBackgroundColor)

            if (Math.abs(bgLightness - dimmerLightness) > Math.abs(bgLightness - highBgLightness)) {
                verticalScrollDecorator.color = Theme.highlightDimmerColor
                horizontalScrollDecorator.color = Theme.highlightDimmerColor
            } else {
                verticalScrollDecorator.color = Theme.highlightBackgroundColor
                horizontalScrollDecorator.color = Theme.highlightBackgroundColor
            }

            sendAsyncMessage("Browser:SelectionColorUpdate",
                             {
                                 "color": Theme.secondaryHighlightColor
                             })
        }

        onViewInitialized: {
            addMessageListener("chrome:linkadded")
            addMessageListener("embed:alert")
            addMessageListener("embed:confirm")
            addMessageListener("embed:prompt")
            addMessageListener("embed:auth")
            addMessageListener("embed:login")
            addMessageListener("embed:permissions")
            addMessageListener("Content:ContextMenu")
            addMessageListener("Content:SelectionRange");
            addMessageListener("Content:SelectionCopied");
            addMessageListener("embed:selectasync")

            loadFrameScript("chrome://embedlite/content/SelectAsyncHelper.js")
            loadFrameScript("chrome://embedlite/content/embedhelper.js")

            if (WebUtils.initialPage !== "") {
                browserPage.load(WebUtils.initialPage)
            } else if (historyModel.count == 0 ) {
                browserPage.load(WebUtils.homePage)
            } else {
                browserPage.load(tab.url)
            }
        }

        onDraggingChanged: {
            if (dragging && loading) {
                userHasDraggedWhileLoading = true
            }
        }

        onLoadedChanged: {
            if (loaded) {
                if (url != "about:blank" && url) {
                    // This is always up-to-date in both link clicked and back/forward navigation
                    // captureScreen does not work here as we might have changed to TabPage.
                    // Tab icon clicked takes care of the rest.
                    tab.updateTab(browserPage.url, browserPage.title, "")
                }

                if (!userHasDraggedWhileLoading) {
                    webContainer.resetHeight(false)
                }
            }
        }

        onLoadingChanged: {
            if (loading) {
                userHasDraggedWhileLoading = false
                favicon = ""
                webView.chrome = true
                webContainer.resetHeight(false)
            }
        }
        onRecvAsyncMessage: {
            switch (message) {
            case "chrome:linkadded": {
                if (data.rel === "shortcut icon") {
                    favicon = data.href
                }
                break
            }
            case "embed:selectasync": {
                var dialog

                dialog = pageStack.push(Qt.resolvedUrl("components/SelectDialog.qml"),
                                        {
                                            "options": data.options,
                                            "multiple": data.multiple,
                                            "webview": webView
                                        })
                break;
            }
            case "embed:alert": {
                var winid = data.winid
                var dialog = pageStack.push(Qt.resolvedUrl("components/AlertDialog.qml"),
                                            {"text": data.text})
                // TODO: also the Async message must be sent when window gets closed
                dialog.done.connect(function() {
                    sendAsyncMessage("alertresponse", {"winid": winid})
                })
                break
            }
            case "embed:confirm": {
                var winid = data.winid
                var dialog = pageStack.push(Qt.resolvedUrl("components/ConfirmDialog.qml"),
                                            {"text": data.text})
                // TODO: also the Async message must be sent when window gets closed
                dialog.accepted.connect(function() {
                    sendAsyncMessage("confirmresponse",
                                     {"winid": winid, "accepted": true})
                })
                dialog.rejected.connect(function() {
                    sendAsyncMessage("confirmresponse",
                                     {"winid": winid, "accepted": false})
                })
                break
            }
            case "embed:prompt": {
                var winid = data.winid
                var dialog = pageStack.push(Qt.resolvedUrl("components/PromptDialog.qml"),
                                            {"text": data.text, "value": data.defaultValue})
                // TODO: also the Async message must be sent when window gets closed
                dialog.accepted.connect(function() {
                    sendAsyncMessage("promptresponse",
                                     {
                                         "winid": winid,
                                         "accepted": true,
                                         "promptvalue": dialog.value
                                     })
                })
                dialog.rejected.connect(function() {
                    sendAsyncMessage("promptresponse",
                                     {"winid": winid, "accepted": false})
                })
                break
            }
            case "embed:auth": {
                if (pageStack.busy) {
                    // User has just entered wrong credentials and webView wants
                    // user's input again immediately even thogh the accepted
                    // dialog is still deactivating.
                    browserPage._authData = data
                    // A better solution would be to connect to browserPage.statusChanged,
                    // but QML Page transitions keep corrupting even
                    // after browserPage.status === PageStatus.Active thus auxTimer.
                    auxTimer.triggered.connect(browserPage.openAuthDialog)
                    auxTimer.start()
                } else {
                    browserPage.openAuthDialog(data)
                }
                break
            }
            case "embed:permissions": {
                // Ask for location permission
                var dialog = pageStack.push(Qt.resolvedUrl("components/LocationDialog.qml"),
                                            {})
                dialog.accepted.connect(function() {
                    sendAsyncMessage("embedui:premissions", {
                                         allow: true,
                                         checkedDontAsk: false,
                                         id: data.id })
                })
                dialog.rejected.connect(function() {
                    sendAsyncMessage("embedui:premissions", {
                                         allow: false,
                                         checkedDontAsk: false,
                                         id: data.id })
                })
                break
            }
            case "embed:login": {
                pageStack.push(Qt.resolvedUrl("components/PasswordManagerDialog.qml"),
                               {
                                   "webView": webView,
                                   "requestId": data.id,
                                   "notificationType": data.name,
                                   "formData": data.formdata
                               })
                break
            }
            case "Content:ContextMenu": {
                webView.contextMenuRequested(data)
                if (data.types.indexOf("image") !== -1 || data.types.indexOf("link") !== -1) {
                    openContextMenu(data.linkURL, data.mediaURL, data.linkTitle, data.contentType)
                }
                break
            }
            case "Content:SelectionRange": {
                webView.selectionRangeUpdated(data)
                break
            }
            }
        }
        onRecvSyncMessage: {
            // sender expects that this handler will update `response` argument
            switch (message) {
            case "Content:SelectionCopied": {
                webView.selectionCopied(data)

                if (data.succeeded) {
                    //% "Copied to clipboard"
                    notification.show(qsTrId("sailfish_browser-la-selection_copied"))
                }
                break
            }
            }
        }

        // We decided to disable "text selection" until we understand how it
        // should look like in Sailfish.
        // TextSelectionController {}

        Rectangle {
            id: verticalScrollDecorator

            width: 5
            height: webView.verticalScrollDecorator.height
            y: webView.verticalScrollDecorator.y
            anchors.right: parent ? parent.right: undefined
            color: Theme.highlightDimmerColor
            smooth: true
            radius: 2.5
            visible: webView.contentHeight > webView.height && !webView.pinching && !_ctxMenuActive
            opacity: webView.moving ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
        }

        Rectangle {
            id: horizontalScrollDecorator
            width: webView.horizontalScrollDecorator.width
            height: 5
            x: webView.horizontalScrollDecorator.x
            y: browserPage.height - (fullscreenMode ? 0 : toolBarContainer.height) - height
            color: Theme.highlightDimmerColor
            smooth: true
            radius: 2.5
            visible: webView.contentWidth > webView.width && !webView.pinching && !_ctxMenuActive
            opacity: webView.moving ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
        }

        states: State {
            name: "boundHeightControl"
            when: webContainer.inputPanelVisible || !webContainer.foreground
            PropertyChanges {
                target: webView
                height: browserPage.height
            }
        }
    }

    Column {
        id: controlArea

        // This should be just a binding for progressBar.progress but currently progress is going up and down
        property real loadProgress: webView.loadProgress / 100.0

        anchors.bottom: webContainer.bottom
        width: parent.width
        visible: !_ctxMenuActive
        opacity: fullscreenMode ? 0.0 : 1.0
        Behavior on opacity { FadeAnimation { duration: webContainer.foreground ? 300 : 0 } }

        onLoadProgressChanged: {
            if (loadProgress > progressBar.progress) {
                progressBar.progress = loadProgress
            }
        }

        function openTabPage(focus, operationType) {
            if (browserPage.status === PageStatus.Active) {
                captureScreen()
                pageStack.push(Qt.resolvedUrl("TabPage.qml"), {"browserPage" : browserPage, "initialSearchFocus": focus }, operationType)
            }
        }

        Browser.StatusBar {
            width: parent.width
            height: visible ? toolBarContainer.height * 3 : 0
            opacity: progressBar.opacity
            title: browserPage.title
            url: browserPage.url
            onSearchClicked: controlArea.openTabPage(true, PageStackAction.Animated)
            onCloseClicked: {
                closeTab(currentTabIndex)
                if (!tabModel.count) {
                    browserPage.title = ""
                    browserPage.url = ""
                    pageStack.push(Qt.resolvedUrl("TabPage.qml"), {"browserPage" : browserPage, "initialSearchFocus": true })
                }
            }
        }

        Browser.ToolBarContainer {
            id: toolBarContainer
            width: parent.width
            enabled: !fullscreenMode

            Browser.ProgressBar {
                id: progressBar
                anchors.fill: parent
                opacity: webView.loading ? 1.0 : 0.0
            }

            // ToolBar
            Row {
                anchors {
                    left: parent.left; leftMargin: Theme.paddingMedium
                    right: parent.right; rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                // 5 icons, 4 spaces between
                spacing: (width - (backIcon.width * 5)) / 4

                Browser.IconButton {
                    id:backIcon
                    source: "image://theme/icon-m-back"
                    enabled: tab.canGoBack
                    onClicked: {
                        tab.backForwardNavigation = true
                        tab.goBack()
                    }
                }

                Browser.IconButton {
                    property bool favorited: favorites.count > 0 && favorites.contains(tab.url)
                    source: favorited ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                    onClicked: {
                        if (favorited) {
                            favorites.removeBookmark(tab.url)
                        } else {
                            favorites.addBookmark(tab.url, tab.title, favicon)
                        }
                    }
                }

                Browser.IconButton {
                    id: tabPageButton
                    source: "image://theme/icon-m-tabs"
                    onClicked: controlArea.openTabPage(false, PageStackAction.Animated)

                    Label {
                        text: tabs.count
                        x: (parent.width - contentWidth) / 2 - 5
                        y: (parent.height - contentHeight) / 2 - 5
                        font.pixelSize: Theme.fontSizeExtraSmall
                        font.bold: true
                        color: tabPageButton.down ? Theme.highlightColor : Theme.highlightDimmerColor
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Browser.IconButton {
                    source: webView.loading ? "image://theme/icon-m-reset" : "image://theme/icon-m-refresh"
                    onClicked: webView.loading ? webView.stop() : webView.reload()
                }

                Browser.IconButton {
                    source: "image://theme/icon-m-forward"
                    enabled: tab.canGoForward
                    onClicked: {
                        tab.backForwardNavigation = true
                        tab.goForward()
                    }
                }
            }
        }
    }

    CoverActionList {
        enabled: browserPage.status === PageStatus.Active
        iconBackground: true

        CoverAction {
            iconSource: "image://theme/icon-cover-new"
            onTriggered: {
                controlArea.openTabPage(false, PageStackAction.Immediate)
                activate()
            }
        }

        CoverAction {
            iconSource: webView.loading ? "image://theme/icon-cover-cancel" : "image://theme/icon-cover-refresh"
            onTriggered: {
                if (webView.loading) {
                    webView.stop()
                } else {
                    webView.reload()
                }
            }
        }
    }

    Connections {
        target: WebUtils
        onOpenUrlRequested: {
            if (webView.url != "") {
                captureScreen()
                if (!tabs.activateTab(url)) {
                    // Not found in tabs list, create newtab and load
                    newTab(url, true)
                }
            } else {
                // New browser instance, just load the content
                load(url)
            }
            if (status != PageStatus.Active) {
                pageStack.pop(browserPage, PageStackAction.Immediate)
            }
            if (!window.applicationActive) {
                window.activate()
            }
        }
    }

    BookmarkModel {
        id: favoriteModel
    }

    Timer {
        id: auxTimer

        interval: 1000
    }

    Browser.BrowserNotification {
        id: notification
    }

    NetworkManager {
        id: networkManager

        property bool reloadNeeded

        onStateChanged: {
            if (reloadNeeded && (networkManager.state === "online" || networkManager.state === "ready")) {
                webView.reload()
                reloadNeeded = false
            }
        }
    }
}
