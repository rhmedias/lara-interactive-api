l = (require './log').instance()
iframePhone = require 'iframe-phone'

getParameterByName = (name, defaultValue="") ->
  name    = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]")
  regex   = new RegExp("[\\?&]#{name}=([^&#]*)")
  results = regex.exec(location.search)
  if results == null
    return defaultValue
  return decodeURIComponent(results[1].replace(/\+/g, " "))

module.exports = class Wrapper
  constructor: (id) ->
    @globalState = {}
    @updateRuntimeDataSchedule = false
    @updateInterval = 500 # 0.5s
    @loadConfiguration()
    $(id).attr('src', @interactiveUrl)
    $(id).load () =>
      l.info "loaded interactive #{@interactiveUrl}"
      @registerPhones(id)

  loadConfiguration: () ->
    @datasetName = getParameterByName "datasetName", "prediction-dataset"
    l.info "Using dataset #{@datasetName}"

    @globalStateKey = getParameterByName "globalStateKey", "gstate-prediction-dataset"
    l.info "Global key #{@globalStateKey}"

    @interactiveUrl = getParameterByName "interactive", "http://lab.concord.org/embeddable.html#interactives/itsi/sensor/prediction-prediction.json"
    l.info "Interactive #{@interactiveUrl}"

  registerPhones: (id) ->
    if @interactivePhone
      @interactivePhone.hangup()
      @interactivePhone = null

    if @runtimePhone
      @runtimePhone.hangup()
      @runtimePhone = null


    @interactivePhone = new iframePhone.ParentEndpoint $(id)[0], =>
      @interactivePhoneAnswered()
      l.info "Interactive Phone ready"

      # register LARA side:
      @runtimePhone = new iframePhone.getIFrameEndpoint()
      @registerHandlers(@runtimePhone, @runtimeHandlers())
      l.info "Runtime Phone ready"
      @runtimePhone.initialize()

  # Batch-up changes by starting a timer when data changes.
  # Notify change when timer runs out.
  # delay if new data is continuing to come in.
  scheduleDataUpdate: ->
    if @updateRuntimeDataSchedule
      clearTimeout(@updateRuntimeDataSchedule)
    func = =>
      @interactivePhone.post 'getDataset', @datasetName
      @updateRuntimeDataSchedule = false
    @updateRuntimeDataSchedule = setTimeout func, @updateInterval

  runtimeHandlers: ->
    "loadInteractiveGlobal": (data) =>
      data = JSON.parse(data) if typeof data is 'string'
      @globalState = data
      myData = @globalState[@globalStateKey]
      if myData
        @interactivePhone.post 'sendDatasetEvent',
          "eventName": 'dataReset'
          "datasetName": @datasetName
          "data": myData.value.initialData

    "getLearnerUrl": (data) =>
      l.info "GetLearnerUrl heard"
      @runtimePhone.post "setLearnerUrl", "http://wrapper.com/fakeout"

  interactiveHandlers: ->
    "#{@datasetName}-sampleAdded": =>
      @scheduleDataUpdate()
    "#{@datasetName}-sampleRemoved": =>
      @scheduleDataUpdate()
    "#{@datasetName}-dataReset":=>
      @scheduleDataUpdate()
    "modelLoaded": () =>
      l.info("Model loaded called")
      @runtimePhone.post('interactiveStateGlobal', @globalState)
    "dataset": (data)=>
      @globalState[@globalStateKey] = data
      @runtimePhone.post('interactiveStateGlobal', @globalState)

  interactivePhoneAnswered: ()->
    if @alreadySetupInteractive
      l.info "interactive phone rang, and previously answerd"
    else
      l.info "interactive phone answered"
      @alreadySetupInteractive = true
      @registerHandlers(@interactivePhone, @interactiveHandlers())
      reg = (evt) =>
        l.info("wiring a request for #{evt}")
        @interactivePhone.post "listenForDatasetEvent",
          eventName: evt
          datasetName: @datasetName
      events = "sampleAdded dataReset sampleRemoved".split /\s+/
      reg(evnt) for evnt in events


  registerHandlers: (phone, handlers) ->
    register = (phone, message, response) =>
      phone.addListener message, (data) =>
        l.info "handling phone: #{message}"
        if response
          response(data)
        else
          l.info "no response defined for #{message}"
    register(phone,message, response) for message, response of handlers


window.Wrapper = Wrapper