class ConnectionView extends Marionette.ItemView
    className: 'connection-view'
    template: _.template """
        <p>Select a Whisper capable Ethereum node to connect to:</p>
        <div class="server selected">
        <div class="row">
            Host: <span class="host">localhost</span>
        </div>
        <div class="row">
            Port: <span class="port">8545</span>
        </div>
        </div>
        <div class="server">
        <div class="row">
            Host: <input class="host" type="text" value="eth.datagotchi.com" />
        </div>
        <div class="row">
            Port: <input class="port" type="number" value="80" />
        </div>
        </div>
        <button class="connect">Connect</button>
    """
    events:
        'click .server': '_handleSelectServer'
        'click button.connect': '_handleClickConnect'

    _handleClickConnect: ->
        host = @$('.server.selected .host').val?() or $('.server.selected .host').text()
        port = @$('.server.selected .port').val?() or $('.server.selected .port').text()
        @connection = new Connection( {host, port} )
        @listenToOnce( @connection, 'connected', @_handleConnected )
        @connection.connect()

    _handleSelectServer: (ev) ->
        @$( '.server' ).removeClass('selected')
        @$( ev.target ).closest('.server').addClass('selected')

    _handleConnected: ->
        @trigger('connected')


class MessageView extends Marionette.ItemView
    className: 'message-view'
    template: _.template """
        <span class="sent"><%- getTime() %></span>
        <span class="from"><%- from %></span>
        <span class="payload"><%- payload[0] %></span>
    """

    templateHelpers:
        getTime: ->
            time = new Date( @sent )
            "#{ time.getHours() }:#{ time.getMinutes() }"

class MessagesCollectionView extends Marionette.CollectionView
    className: 'messages-view'
    childView: MessageView

class Channel extends Backbone.Model
    initialize: ({@name}) ->
        @collection = new Backbone.Collection()

    join: ->
        @_createFilter()
        @trigger('join')

    leave: ->
        @_removeFilter()
        @trigger('leave')

    sendMessage: (message) =>
        console.log message
        message.topics = [@get('name')]
        web3.shh.post( message )

    _createFilter: ->
        return if @filter
        console.log "Creating filter for channel: ##{@get('name')}"
        @filter = web3.shh.filter( topics: [ @get('name') ] )
        @filter.watch( @_handleNewMessage )

    _handleNewMessage: (err,resp) =>
        console.log "Message for channel: ##{ @get('name') }", arguments
        @collection.add( resp ) unless err

    _removeFilter: ->
        @filter?.stopWatching()
        delete @filter


class ChannelsChannel extends Channel
    initialize: ({@name, @collection }) ->

    _handleNewMessage: (err,resp) =>
        return unless resp?.payload[0]
        console.log( 'Channel discovered: #', resp?.payload[0] )
        @collection.add( new Channel( { name: resp?.payload[0] } ) )
        


class Channels extends Backbone.Collection
    model: Channel



class ChannelItemView extends Marionette.ItemView
    tagName: 'li'
    className: 'channel-item-view'
    template: _.template """
        <span class="name"><%- name %></span>
        <button class="join-channel">join</button>
        <button class="leave-channel">leave</button>
    """
    triggers:
        'click .join-channel': 'join:channel'
        'click .leave-channel': 'leave:channel'
        'click .name': 'select:channel'

    modelEvents:
        'join': -> @$el.addClass('joined')
        'leave': -> @$el.removeClass('joined')


class ChannelsView extends Marionette.CollectionView
    tagName: 'ul'
    className: 'channels-view'
    childView: ChannelItemView
    childEvents:
        'select:channel': '_handleSelectChannel'
        'join:channel': '_handleJoinChannel'
        'leave:channel': '_handleLeaveChannel'
        
    initialize: ({@outputRegion, @inputRegion, @identity, @collection}) ->
        @channelsChannel = new ChannelsChannel( name: 'psst', collection: @collection )
        @channelsChannel.join()

    _handleSelectChannel: (childView, {model}) ->
        model.join()
        @outputRegion.show new MessagesCollectionView
            collection: model.collection
        @inputRegion.show new InputView
            model: model
            identity: @identity

    _handleLeaveChannel: (childView, {model})->
        model.leave()

    _handleJoinChannel: (childView, {model}) ->
        @channelsChannel.sendMessage
            ttl: 1000
            payload: [ model.get('name') ]
        @_handleSelectChannel( childView, {model} )


class InputView extends Marionette.ItemView
    className: 'input-view'
    template: _.template """
        <textarea placeholder="Type something..."></textarea>
    """
    events:
        'keypress textarea': '_handleKeyPress'
    initialize: ({@model, @identity}) ->

    _handleKeyPress: (ev) =>
        if ev.keyCode is 13
            @model.sendMessage
                payload: [ev.target.value]
                ttl: 100
                from: @identity

            ev.target.value = ""


class AppView extends Marionette.LayoutView
    className: 'app-view'
    template: _.template """
    <div id="overlay"></div>
    <div id="chat">
        <div id="channels">
            <h1>Psst</h1>
            <div id="server" class="">
                Host: <span class="host"></span>:<span class="port"></span>
                <br/>
                <span class="status"></span>
            </div>
            <div>Channels: <input type="text" class="create-channel" placeholder="Create channel"></input></div>
            <div id="channels-region"></div>
        </div>
        <div id="output-region"></div>
        <div id="input-region"></div>
    </div>
    """
    regions:
        overlayRegion: '#overlay'
        outputRegion: '#output-region'
        inputRegion: '#input-region'
        channelsRegion: '#channels-region'

    events:
        'keypress .create-channel': '_handleCreateChannel'
        'click h1': ->
            console.log( this )

    onShow: ->
        connectionView = new ConnectionView()
        @listenTo( connectionView, 'connected', @_handleConnected )
        @overlayRegion.show( connectionView )

    _handleConnected: ->
        @overlayRegion.empty()
        @channelsView = new ChannelsView
            identity: web3.shh.newIdentity()
            outputRegion: @outputRegion
            collection: new Channels([new Channel( name: 'd11e9' )])
            inputRegion: @inputRegion
        @channelsRegion.show( @channelsView )

    _handleCreateChannel: (ev) =>
        return unless ev.keyCode is 13
        channelName = $(ev.target).val()
        @channelsView.channelsChannel.sendMessage
            ttl: 1000
            payload: [channelName]


class Connection extends Backbone.Model
    initialize: ({@host, @port}) ->

    connect: ->
        document.querySelector('#server .host').innerHTML = @host
        document.querySelector('#server .port').innerHTML = @port

        hostStatus = "Connecting..."
        try
            endpoint = "http://#{ @host }:#{ @port }"
            httpProvider = new web3.providers.HttpProvider( endpoint )
            web3.setProvider( httpProvider )
        catch err
            hostStatus = "Failed!"

        try
            hostStatus = "Connected" if web3.eth.coinbase
            console.log "Connected!!!"
            @trigger('connected')
        catch err
            hostStatus = "Failed!"

        document.querySelector('#server .status').innerHTML = hostStatus


appRegion = new Marionette.Region( el: $('body')[0] )
appRegion.show( new AppView() )

        