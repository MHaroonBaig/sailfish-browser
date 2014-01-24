/****************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Vesa-Matti Hartikainen <vesa-matti.hartikainen@jollamobile.com>
**
****************************************************************************/


import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Browser 1.0
import org.nemomobile.connectivity 1.0
import "components" as Browser


Page {
    id: browserPage

    property Item firstUseOverlay
    property alias tabs: tabModel
    property alias favorites: favoriteModel
    property alias history: historyModel
    property alias viewLoading: webView.loading
    property alias currentTab: tab
    property string title
    property string url

    property string favicon
    property Item _contextMenu
    property bool _ctxMenuActive: _contextMenu != null && _contextMenu.active
    // As QML can't disconnect closure from a signal (but methods only)
    // let's keep auth data in this auxilary attribute whose sole purpose is to
    // pass arguments to openAuthDialog().
    property var _authData: null
    property var _deferredLoad: null
    property bool _deferredReload

    // Used by newTab function
    property bool newTabRequested

    function newTab(url, foreground, title) {
        if (foreground) {
            // This might be something that we don't want to have.
            if (webView.loading) {
                webView.stop()
            }
            tab.loadWhenTabChanges = true
            captureScreen()
        }
        // tabMovel.addTab does not trigger anymore navigateTo call. Always done via
        // QmlMozView onUrlChanged handler.
        // Loading newTabs seems to be broken. When an url that was already loaded is loaded again and still
        // active in one of the tabs, the tab containing the url is not brought to foreground.
        // This was broken already before this change. We need to add mapping between intented
        // load url and actual result url to TabModel::activateTab so that finding can be done.
        newTabRequested = true
        tabModel.addTab(url, foreground)
        load(url, title)
    }

    function closeTab(index, loadActive) {
        if (tabModel.count == 0) {
            return
        }

        if (webView.loading) {
            webView.stop()
        }

        tab.loadWhenTabChanges = loadActive
        tabModel.remove(index)
    }

    function closeActiveTab(loadActive) {
        if (tabModel.count === 0) {
            return
        }

        if (webView.loading) {
            webView.stop()
        }

        tab.loadWhenTabChanges = loadActive
        tabModel.closeActiveTab();

        if (tabModel.count === 0 && browserPage.status === PageStatus.Active) {
            browserPage.title = ""
            browserPage.url = ""
            pageStack.push(Qt.resolvedUrl("TabPage.qml"), {"browserPage" : browserPage, "initialSearchFocus": true })
        }
    }

    function reload() {
        var url = browserPage.url

        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !browserPage._deferredReload
            && !connectionHelper.haveNetworkConnectivity()) {

            browserPage._deferredReload = true
            browserPage._deferredLoad = null
            connectionHelper.attemptToConnectNetwork()
            return
        }

        webView.reload()
    }

    function load(url, title, force) {
        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !connectionHelper.haveNetworkConnectivity()
            && !browserPage._deferredLoad) {

            browserPage._deferredReload = false
            browserPage._deferredLoad = {
                "url": url,
                "title": title
            }
            connectionHelper.attemptToConnectNetwork()
            return
        }

        if (tabModel.count == 0) {
            newTabRequested = true
            tabModel.addTab(url, true)
        }

        if (title) {
            browserPage.title = title
        } else {
            browserPage.title = ""
        }

        // Always enable chrome when load is called.
        webView.chrome = true

        if ((url !== "" && webView.url != url) || force) {
            browserPage.url = url
            resourceController.firstFrameRendered = false
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
        tabModel.activateTab(index)
        // When tab is loaded we always pop back to BrowserPage.
        pageStack.pop(browserPage)
    }

    function deleteTabHistory() {
        historyModel.clear()
    }

    function captureScreen() {
        if (status == PageStatus.Active && resourceController.firstFrameRendered) {
            var size = Screen.width
            if (browserPage.isLandscape && !webView.fullscreenMode) {
                size -= toolbarRow.height
            }

            tab.captureScreen(webView.url, 0, 0, size, size, browserPage.rotation)
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
                                                            "contentType": contentType,
                                                            "viewId": webView.uniqueID()
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
    clip: status != PageStatus.Active || webView.inputPanelVisible

    orientationTransitions: Transition {
        to: 'Portrait,Landscape,LandscapeInverted'
        from: 'Portrait,Landscape,LandscapeInverted'
        SequentialAnimation {
            PropertyAction {
                target: browserPage
                property: 'orientationTransitionRunning'
                value: true
            }
            ParallelAnimation {
                FadeAnimation {
                    target: webView.contentItem
                    to: 0
                    duration: 150
                }
                FadeAnimation {
                    target: !fullscreenMode ? controlArea : null
                    to: 0
                    duration: 150
                }
            }
            PropertyAction {
                target: browserPage
                properties: 'width,height,rotation,orientation'
            }
            ScriptAction {
                script: {
                    // Restores the Bindings to width, height and rotation
                    _defaultTransition = false
                    webView.resetHeight(true)
                    _defaultTransition = true
                }
            }
            FadeAnimation {
                target: !fullscreenMode ? controlArea : null
                to: 1
                duration: 150
            }
            // End-2-end implementation for OnUpdateDisplayPort should
            // give better solution and reduce visible relayoutting.
            FadeAnimation {
                target: webView.contentItem
                to: 1
                duration: 850
            }
            PropertyAction {
                target: browserPage
                property: 'orientationTransitionRunning'
                value: false
            }
        }
    }

    TabModel {
        id: tabModel
        currentTab: tab
        browsing: browserPage.status === PageStatus.Active
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
    Browser.ResourceController {
        id: resourceController
        webView: webView
        background: webView.background

        onWebViewSuspended: {
            connectionHelper.closeNetworkSession()
        }

        onFirstFrameRenderedChanged: {
            if (firstFrameRendered) {
                captureScreen()
            }
        }
    }

    Browser.WebView {
        id: webView
    }


    Column {
        id: controlArea

        // This should be just a binding for progressBar.progress but currently progress is going up and down
        property real loadProgress: webView.loadProgress / 100.0

        anchors.bottom: webView.bottom
        width: parent.width

        visible: !_ctxMenuActive
        opacity: webView.fullscreenMode ? 0.0 : 1.0
        Behavior on opacity { FadeAnimation { duration: webView.foreground ? 300 : 0 } }

        onLoadProgressChanged: {
            if (loadProgress > progressBar.progress) {
                progressBar.progress = loadProgress
            }
        }

        function openTabPage(focus, newTab, operationType) {
            if (browserPage.status === PageStatus.Active) {
                captureScreen()
                pageStack.push(Qt.resolvedUrl("TabPage.qml"),
                               {
                                   "browserPage" : browserPage,
                                   "initialSearchFocus": focus,
                                   "newTab": newTab
                               }, operationType)
            }
        }

        Browser.StatusBar {
            width: parent.width
            height: visible ? toolBarContainer.height * 3 : 0
            visible: isPortrait
            opacity: progressBar.opacity
            title: browserPage.title
            url: browserPage.url
            onSearchClicked: controlArea.openTabPage(true, false, PageStackAction.Animated)
            onCloseClicked: browserPage.closeActiveTab(true)
        }

        Browser.ToolBarContainer {
            id: toolBarContainer
            width: parent.width
            enabled: !webView.fullscreenMode

            Browser.ProgressBar {
                id: progressBar
                anchors.fill: parent
                opacity: webView.loading ? 1.0 : 0.0
            }

            // ToolBar
            Row {
                id: toolbarRow

                anchors {
                    left: parent.left; leftMargin: Theme.paddingMedium
                    right: parent.right; rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }

                // 5 icons, 4 spaces between
                spacing: isPortrait ? (width - (backIcon.width * 5)) / 4 : Theme.paddingSmall

                Browser.IconButton {
                    visible: isLandscape
                    source: "image://theme/icon-m-close"
                    onClicked: browserPage.closeActiveTab(true)
                }

                // Spacer
                Item {
                    visible: isLandscape
                    height: Theme.itemSizeSmall
                    width: browserPage.width
                           - toolbarRow.spacing * (toolbarRow.children.length - 1)
                           - backIcon.width * (toolbarRow.children.length - 1)
                           - parent.anchors.leftMargin
                           - parent.anchors.rightMargin

                    Browser.TitleBar {
                        url: browserPage.url
                        title: browserPage.title
                        height: parent.height
                        onClicked: controlArea.openTabPage(true, false, PageStackAction.Animated)
                        // Workaround for binding loop jb#15182
                        clip: true
                    }
                }

                Browser.IconButton {
                    id: backIcon
                    source: "image://theme/icon-m-back"
                    enabled: tab.canGoBack
                    onClicked: {
                        tab.backForwardNavigation = true
                        tab.goBack()
                    }
                }

                Browser.IconButton {
                    enabled: WebUtils.firstUseDone
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
                    onClicked: controlArea.openTabPage(false, false, PageStackAction.Animated)

                    Label {
                        visible: tabModel.count > 0
                        text: tabModel.count
                        x: (parent.width - contentWidth) / 2 - 5
                        y: (parent.height - contentHeight) / 2 - 5
                        font.pixelSize: Theme.fontSizeExtraSmall
                        font.bold: true
                        color: tabPageButton.down ? Theme.highlightDimmerColor : Theme.highlightColor
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Browser.IconButton {
                    enabled: WebUtils.firstUseDone
                    source: webView.loading ? "image://theme/icon-m-reset" : "image://theme/icon-m-refresh"
                    onClicked: webView.loading ? webView.stop() : browserPage.reload()
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
                controlArea.openTabPage(true, true, PageStackAction.Immediate)
                activate()
            }
        }

        CoverAction {
            iconSource: webView.loading ? "image://theme/icon-cover-cancel" : "image://theme/icon-cover-refresh"
            onTriggered: {
                if (webView.loading) {
                    webView.stop()
                } else {
                    browserPage.reload()
                }
            }
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Inactive && !WebUtils.firstUseDone) {
            WebUtils.firstUseDone = true
        }
    }

    Connections {
        target: WebUtils
        onOpenUrlRequested: {
            if (url == "") {
                // User tapped on icon when browser was already open.
                // let's just bring the browser to front
                if (!window.applicationActive) {
                    window.activate()
                }
                return
            }
            if (webView.url != "") {
                captureScreen()
                if (!tabModel.activateTab(url)) {
                    // Not found in tabs list, create newtab and load
                    newTab(url, true)
                }
            } else {
                // New browser instance, just load the content
                if (WebUtils.firstUseDone) {
                    load(url)
                } else {
                    tabModel.addTab(url, false)
                }
            }
            if (browserPage.status !== PageStatus.Active) {
                pageStack.pop(browserPage, PageStackAction.Immediate)
            }
            if (!window.applicationActive) {
                window.activate()
            }
        }
        onFirstUseDoneChanged: {
            if (WebUtils.firstUseDone && firstUseOverlay) {
                firstUseOverlay.destroy()
            }
        }
    }

    Component.onCompleted: {
        if (!WebUtils.firstUseDone) {
            var component = Qt.createComponent(Qt.resolvedUrl("components/FirstUseOverlay.qml"))
            if (component.status == Component.Ready) {
                firstUseOverlay = component.createObject(browserPage, {"width": browserPage.width, "height": browserPage.height - toolBarContainer.height });
            } else {
                console.log("FirstUseOverlay create failed " + component.status)
            }
        }
    }

    Component.onDestruction: {
        connectionHelper.closeNetworkSession()
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

    ConnectionHelper {
        id: connectionHelper

        onNetworkConnectivityEstablished: {
            var url
            var title

            if (browserPage._deferredLoad) {
                url = browserPage._deferredLoad["url"]
                title = browserPage._deferredLoad["title"]
                browserPage._deferredLoad = null

                browserPage.load(url, title, true)
            } else if (browserPage._deferredReload) {
                browserPage._deferredReload = false
                webView.reload()
            }
        }

        onNetworkConnectivityUnavailable: {
            browserPage._deferredLoad = null
            browserPage._deferredReload = false
        }
    }
}
