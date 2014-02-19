cluster = require 'cluster'
path = require 'path'
os = require 'os'
net = require 'net'
fs = require 'fs'
util = require 'util'
_ = require 'lodash-fork'
require 'debug-fork'
Repl = require './repl'
debug = global.debug 'cluster-master'
debugError = global.debug 'error'

module.exports = class ClusterMaster
  constructor: (config) ->
    return new ClusterMaster config if this is global

    @setupConfig(config)
    @setupCluster()

    process.on 'SIGHUP', => @restart()
    process.on 'SIGINT', => @quit()
    process.on 'exit', => @quitHard() unless @quitting

    @repl = new Repl this, @config.repl

    @resize @config.size, => @repl.start()

  setupConfig: (config=0) ->
    throw new Error("Must define a 'exec' script")  unless config.exec
    throw new Error("ClusterMaster answers to no one!\n" + "(don't run in a cluster worker script)")  unless cluster.isMaster

    config = exec: config if typeof config is 'string'

    out = _.defaults {}, config,
      minRestartAge: 2000
      size: os.cpus().length
      repl: process.env.CLUSTER_MASTER_REPL or 'cluster-master-socket'
      maxTermMillis: 10000

    out.exec = path.resolve config.exec
    @config = out

  setupCluster: ->
    cluster.setupMaster @config
    throw new Error("This cluster already has a cluster-master instance running")  if cluster._clusterMaster
    cluster._clusterMaster = this

    cluster.on 'fork', (worker) =>
      worker.birth = Date.now()
      worker.__defineGetter__ 'age', -> Date.now() - @birth
      pid = worker.pid = worker.process.pid
      id = worker.id

      debug "Worker #{id} (#{pid}) starting"

      disconnectTimer = undefined

      worker.on 'exit', =>
        clearTimeout timeout if timeout = worker.disconnectTimer

        if worker.suicide or timeout # an invoked exit -- worker could have received SIGTERM and closed normally
          debug "Worker #{id} (#{pid}) exited."
        else
          debug "Worker #{id} (#{pid}) exited abnormally"

          if worker.age < @config.minRestartAge
            debug "Worker #{id} (#{pid}) died too quickly. Entering 'danger mode.'"
            @danger = true
            setTimeout (=> @resize()), 2000

        if !@danger and Object.keys(cluster.workers).length < @config.size and !@resizing
          @resize()

        return

  debug: debug
  debugError: debugError

  stopWorker: (worker, cb) ->
    if worker.disconnectTimer or !worker or worker.state is 'dead' or !(p = worker.process)
      debug "Stop worker #{worker.id} -- already dead or being killed"
      return cb?()

    debug "Worker #{worker.id} (#{worker.pid}) sending SIGTERM"

    worker.once 'exit', cb if cb
    worker.process.kill "SIGTERM"

    worker.disconnectTimer = setTimeout (=>
      debug "Worker #{worker.id} (#{worker.pid}) took too long to exit. Sending SIGKILL..."
      p.kill "SIGKILL"
    ), @config.maxTermMillis

    return

  resize: (size=@config.size, cb) ->
    return if @resizing
    @resizing = true

    size = 0 if size < 0
    @config.size = size

    workerIds = Object.keys(cluster.workers)
    unless pending = Math.abs(delta = size - workerIds.length)
      @resizing = false
      return cb?()

    didAsync = =>
      return if --pending
      @resizing = false
      if Object.keys(cluster.workers).length isnt size
        if size is 0
          debugError "Workers are alive but 0 cluster size."
          process.exit(1)
        else
          debug "Wrong worker count at end of resize() loop. Entering 'danger mode.'"
          setTimeout (=>@resize()), 1000
        @danger = true
      else
        delete @danger
      return cb?()

    while delta > 0
      debug "Resize forking"
      cluster.once 'online', didAsync
      cluster.fork @config.env
      --delta

    while delta < 0
      worker = workerIds[-delta]
      debug "Resize stopping worker #{worker.id}"
      worker.once 'exit', didAsync
      @stopWorker worker
      ++delta

    return

  quitHard: ->
    @quitting = true
    @quit()

  quit: ->
    if @quitting
      debug "Forceful shutdown"
      p.kill "SIGKILL" for id, worker of cluster.workers when worker and p = worker.process
      process.exit 1

    debug "Graceful shutdown"
    @config.size = 0
    @quitting = true

    count = Object.keys(cluster.workers).length

    workerStopped = =>
      unless --count
        debug "Graceful shutdown successful"
        process.exit 0
      return

    if count
      @stopWorker worker, workerStopped for id, worker of cluster.workers
    else
      ++count
      workerStopped()
    return

  _doRestart: (cb) ->
    return unless size = (workerIds = Object.keys(cluster.workers)).length

    # verify the first one starts and runs for a while, then continue with next()
    cluster.once 'online', (newWorker) =>
      earlyExit = =>
        debugError "Restart: new worker exited too quickly, so aborting restart"
        clearTimeout timer
        @restarting = false
        cb? "Restart failed"
        return

      newWorker.on 'exit', earlyExit

      timer = setTimeout (=>
        worker = cluster.workers[workerIds[0]]
        debug "Restart: first still running. Stopping worker #{worker.id}"
        newWorker.removeListener 'exit', earlyExit
        @stopWorker worker
        next()
      ), 2000

    debug "Restart: forking first"
    cluster.fork @config.env

    next = =>
      i = 0
      while ++i < size
        cluster.once 'online', do (i) => (newWorker) =>
          worker = cluster.workers[workerIds[i]]
          debug "Restart: new worker online. Stopping worker #{worker.id}"
          @stopWorker worker
        cluster.fork @config.env
        debug "Restart: forking next"
      @restarting = false
      return cb?()

    return


  # passes an error if the restart fails, else no arguments
  restart: (cb) ->
    if @restarting
      debug "Already restarting"
      return cb? "EALREADY"

    @restarting = true

    if @config.size isnt Object.keys(cluster.workers).length
      @resize @config.size, (=> @_doRestart cb)
    else
      @_doRestart cb

