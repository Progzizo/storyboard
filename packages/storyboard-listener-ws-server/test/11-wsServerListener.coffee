Promise = require 'bluebird'
http = require 'http'
socketio = require 'socket.io-client'
{removeListener, removeAllListeners, addListener, config, chalk, mainStory} = require 'storyboard'
wsServerListener = require('../lib').default

WS_NAMESPACE = '/STORYBOARD'

#-====================================================
# ## Tests
#-====================================================
if process.env.TEST_BROWSER
  console.log "Skipping #{chalk.cyan.bold 'wsServerListener'} tests in the #{chalk.cyan.bold 'browser'}..."
  return

describe "wsServerListener", ->

  _spySocketRx = null
  before ->
    removeAllListeners()
    config filter: '*:*'
    # _spySocketRx = sinon.spy((msg) -> console.log msg.type)
    _spySocketRx = sinon.spy()

  beforeEach -> _spySocketRx.reset()

  after -> removeAllListeners()

  #-====================================================
  # ### Server without auth
  #-====================================================
  describe "standalone server without authentication", ->

    _listener = null
    _socket = null
    before ->
      _listener = addListener wsServerListener, {throttle: 0}
      return new Promise (resolve, reject) ->
        _socket = socketio "http://localhost:8090#{WS_NAMESPACE}"
        _socket.on 'MSG', _spySocketRx
        _socket.on 'connect', resolve

    after -> removeListener _listener

    it "sanity", ->
      expect(_listener.getConfig().hasOwnProperty('port')).to.be.true

    it "should not require a log in", ->
      _socket.emit 'MSG', {type: 'LOGIN_REQUIRED_QUESTION'}
      waitUntil(1000, -> _spySocketRx.callCount > 0)
      .then (res) ->
        expect(_spySocketRx).to.have.been.calledOnce
        msg = _spySocketRx.args[0][0]
        expect(msg.type).to.equal 'LOGIN_REQUIRED_RESPONSE'
        expect(msg.data.fLoginRequired).to.be.false

    it "should send log records generated via e.g. mainStory.info()", ->
      mainStory.info "Msg through web sockets"
      waitUntil(1000, -> _spySocketRx.callCount > 0)
      .then (res) ->
        expect(_spySocketRx).to.have.been.calledOnce
        msg = _spySocketRx.args[0][0]
        expect(msg.type).to.equal 'RECORDS'
        expect(msg.data).to.have.length 1
        expect(msg.data[0].msg).to.contain 'Msg through web sockets'

    it "should re-broadcast uploaded log records", ->
      _socket.emit 'MSG',
        type: 'RECORDS'
        data: [
          {src: 'fontana di trevi', msg: 'water1'}
        ]
      waitUntil(1000, -> _spySocketRx.callCount > 0)
      .then (res) ->
        expect(_spySocketRx).to.have.been.calledOnce
        msg = _spySocketRx.args[0][0]
        expect(msg.type).to.equal 'RECORDS'
        expect(msg.data).to.have.length 1
        expect(msg.data[0].msg).to.equal 'water1'

    it "should allow setting a new server-side filter and reply", ->
      _socket.emit 'MSG',
        type: 'SET_SERVER_FILTER'
        data: '-*'
      waitUntil(1000, -> _spySocketRx.callCount > 0)
      .then ->
        expect(_spySocketRx).to.have.been.calledOnce
        msg = _spySocketRx.args[0][0]
        expect(msg.type).to.equal 'SERVER_FILTER'
        expect(msg.data).to.deep.equal {filter: '-*'}
      .delay 200  # allow the log message to disappear
      .then -> config filter: '*:*'

    it "should ignore a log out (this is a server without auth)", ->
      _socket.emit 'MSG', {type: 'LOG_OUT'}
      Promise.delay(200)
      .then -> mainStory.info "This message should be received by the client"
      .then -> waitUntil(1000, -> _spySocketRx.callCount > 0)
      .then ->
        expect(_spySocketRx).to.have.been.calledOnce
        msg = _spySocketRx.args[0][0]
        expect(msg.type).to.equal 'RECORDS'


  #-====================================================
  # ### Server with auth
  #-====================================================
  describe "standalone server with authentication", ->
    describe "without throttling", ->

      _listener = null
      _socket = null
      before ->
        _listener = addListener wsServerListener,
          throttle: 0
          authenticate: ({login, password}) -> login is 'admin'
        return new Promise (resolve, reject) ->
          _socket = socketio "http://localhost:8090#{WS_NAMESPACE}"
          _socket.on 'MSG', _spySocketRx
          _socket.on 'connect', resolve

      after -> removeListener _listener

      it "should require a log in", ->
        _socket.emit 'MSG', {type: 'LOGIN_REQUIRED_QUESTION'}
        waitUntil(1000, -> _spySocketRx.callCount > 0)
        .then (res) ->
          expect(_spySocketRx).to.have.been.calledOnce
          msg = _spySocketRx.args[0][0]
          expect(msg.type).to.equal 'LOGIN_REQUIRED_RESPONSE'
          expect(msg.data.fLoginRequired).to.be.true

      it "should reject invalid credentials", ->
        _socket.emit 'MSG', {type: 'LOGIN_REQUEST', data: {login: 'pepinillo', password: 'b'}}
        waitUntil(1000, -> _spySocketRx.callCount > 0)
        .then (res) ->
          expect(_spySocketRx).to.have.been.called
          msg = _spySocketRx.args[0][0]
          expect(msg.type).to.equal 'LOGIN_RESPONSE'
          expect(msg.result).to.equal 'ERROR'
          expect(msg.data?.bufferedRecords).to.be.undefined

      it "should accept a log in (and reply with buffered records)", ->
        _socket.emit 'MSG', {type: 'LOGIN_REQUEST', data: {login: 'admin', password: 'b'}}
        waitUntil(1000, -> _spySocketRx.callCount > 0)
        .then (res) ->
          expect(_spySocketRx).to.have.been.called
          msg = _spySocketRx.args[0][0]
          expect(msg.type).to.equal 'LOGIN_RESPONSE'
          expect(msg.result).to.equal 'SUCCESS'
          expect(msg.data.bufferedRecords).to.be.instanceOf Array

      it "should send log records generated via e.g. mainStory.info()", ->
        mainStory.info "Msg through web sockets"
        waitUntil(1000, -> _spySocketRx.callCount > 0)
        .then (res) ->
          expect(_spySocketRx).to.have.been.calledOnce
          msg = _spySocketRx.args[0][0]
          expect(msg.type).to.equal 'RECORDS'
          expect(msg.data).to.have.length 1
          expect(msg.data[0].msg).to.contain 'Msg through web sockets'

      it "should send log records with attachments", ->
        mainStory.info "Msg with object", attach: {a: 4, b: 3}
        waitUntil(1000, -> _spySocketRx.callCount > 0)
        .then (res) ->
          expect(_spySocketRx).to.have.been.calledOnce
          msg = _spySocketRx.args[0][0]
          expect(msg.type).to.equal 'RECORDS'
          expect(msg.data).to.have.length 1
          expect(msg.data[0].obj).to.deep.equal {a: 4, b: 3}

      it "should report invalid messages", ->
        _socket.emit 'MSG', {type: 'INVALID_MSG_TYPE'}
        waitUntil(1000, -> _spySocketRx.callCount > 0)
        .then (res) ->
          expect(_spySocketRx).to.have.been.calledOnce
          msg = _spySocketRx.args[0][0]
          expect(msg.type).to.equal 'RECORDS'
          expect(msg.data).to.have.length 1
          expect(msg.data[0].msg).to.contain 'Unknown message type'

      it "should accept a log out and no longer send messages", ->
        _socket.emit 'MSG', {type: 'LOG_OUT'}
        Promise.resolve()
        .delay 300
        .then -> mainStory.info "This message should not be received by the client"
        .delay 300
        .then -> expect(_spySocketRx).to.not.have.been.called


    describe "with throttling", ->

      _listener = null
      _socket = null
      before ->
        _listener = addListener wsServerListener,
          throttle: 50
          authenticate: (o) -> true
        return new Promise (resolve, reject) ->
          _socket = socketio "http://localhost:8090#{WS_NAMESPACE}"
          _socket.on 'connect', resolve
          _socket.on 'MSG', _spySocketRx
        .then ->
          _socket.emit 'MSG', {type: 'LOGIN_REQUEST', data: {login: 'a', password: 'b'}}
        .then -> waitUntil(3000, -> _spySocketRx.callCount > 1)  # LOGIN_RESPONSE, initial RECORDS

      after -> removeListener _listener

      it "should send log records generated via e.g. mainStory.info()", ->
        mainStory.info "Msg2 through web sockets"
        waitUntil(3000, -> _spySocketRx.callCount > 0)
        .then (res) ->
          expect(_spySocketRx).to.have.been.calledOnce
          msg = _spySocketRx.args[0][0]
          expect(msg.type).to.equal 'RECORDS'
          # We don't know how many records we will have, just go through them
          foundRecord = null
          for record in msg.data
            if record.msg.indexOf('Msg2 through web sockets') >= 0
              foundRecord = record
              break
          expect(foundRecord).not.to.be.null

  #-====================================================
  # ### Attached server
  #-====================================================
  describe "attached server", ->

    _socket = null
    _spySocketRx = null
    _listener = null
    _httpServer = null
    before ->
      _httpServer = http.createServer(->)
      _spySocketRx = sinon.spy()
      _listener = addListener wsServerListener,
        throttle: 0
        httpServer: _httpServer
      return new Promise (resolve, reject) ->
        _httpServer.on 'listening', resolve
        _httpServer.listen 3000
      .then -> return new Promise (resolve, reject) ->
        _socket = socketio "http://localhost:3000#{WS_NAMESPACE}"
        _socket.on 'MSG', _spySocketRx
        _socket.on 'connect', resolve

    after ->
      removeListener _listener
      _httpServer.close()

    beforeEach -> _spySocketRx.reset()

    it "should send log records generated via e.g. mainStory.info()", ->
      mainStory.info "Msg through web sockets"
      waitUntil(3000, -> _spySocketRx.callCount > 0)
      .then (res) ->
        expect(_spySocketRx).to.have.been.calledOnce
        msg = _spySocketRx.args[0][0]
        expect(msg.type).to.equal 'RECORDS'
        expect(msg.data).to.have.length 1
        expect(msg.data[0].msg).to.contain 'Msg through web sockets'
