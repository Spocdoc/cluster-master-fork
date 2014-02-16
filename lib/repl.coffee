repl = require 'repl'
path = require 'path'
net = require 'net'
fs = require 'fs'
cluster = require 'cluster'
_ = require 'lodash-fork'
require 'debug-fork'
debug = global.debug 'repl'

helpCommands = [
  "help        - display these commands"
  "repl        - access the REPL"
  "resize(n)   - resize the cluster to `n` workers"
  "restart(cb) - gracefully restart workers, cb is optional"
  "stop()      - gracefully stop workers and master"
  "kill()      - forcefully kill workers and master"
  "cluster     - node.js cluster module"
  "size        - current cluster size"
  "connections - number of REPL connections to master"
  "workers     - current workers"
  "select(fld) - map of id to field (from workers)"
  "pids        - map of id to pids"
  "ages        - map of id to worker ages"
  "states      - map of id to worker states"
  "debug(a1)   - output `a1` to stdout and all REPLs"
  "sock        - this REPL socket"
  ".exit       - close this connection to the REPL"
]

class Address
  constructor: (address) ->
    if typeof address is "string"
      # bad form... side-effects
      try
        fs.unlinkSync @address = path.resolve address
        process.on 'exit', =>
          try
            fs.unlinkSync @address
          catch _error
      catch _error
    else if typeof address is "number"
      @port = +address
    else if address
      {@address,@port} = address
    else
      return null

  toString: ->
    "#{@address or ''}#{if @port then ":#{@port}" else ''}"

class Worker
  constructor: (@repl, d) ->
    {@id, @pid, @state, @age} = d

  stop: ->
    @repl.clusterMaster.stopWorker cluster.workers[@id]

  kill: ->
    process.kill @pid


module.exports = class Repl
  constructor: (@clusterMaster, address) ->
    @address = new Address address

  start: ->
    return unless @address
    debug "starting on #{@address}"

    connections = 0
    sockId = 0

    # creates a map from the cluster worker ID to the given field of the cluster worker object
    select = (field) ->
      obj = {}
      obj[id] = worker[field] for id, worker of cluster.workers
      obj

    context =
      help: helpCommands
      cluster: cluster
      # sock: sock

      resize: (n) => @clusterMaster.resize n
      restart: => @clusterMaster.restart()
      stop: => @clusterMaster.quit()
      kill: => @clusterMaster.quitHard()
      select: select

    context.__defineGetter__ 'connections', => connections
    context.__defineGetter__ 'size', => Object.keys(cluster.workers).length
    context.__defineGetter__ 'workers', =>
      obj = {}
      obj[id] = new Worker this, id: id, pid: worker.pid, state: worker.state, age: worker.age for id, worker of cluster.workers
      obj
    context.__defineGetter__ 'pids', => select 'pid'
    context.__defineGetter__ 'ages', => select 'age'
    context.__defineGetter__ 'states', => select 'state'

    @server = server = net.createServer (sock) ->
      ++connections
      sock.id = ++sockId
      sockEnded = replEnded = false
      context.sock = sock

      r = repl.start
        prompt: "ClusterMaster (`help` for cmds) " + process.pid + " " + sock.id + "> "
        input: sock
        output: sock
        terminal: true
        useGlobal: false
        ignoreUndefined: true

      _.extendProps r.context, context

      r.on 'end', ->
        --connections
        replEnded = true
        sock.end() unless sockEnded
        debug "Repl #{sock.id} has ended"

      end = ->
        return if sockEnded
        sockEnded = true
        r.rli.close() unless replEnded

      sock.on 'end', end
      sock.on 'close', end
      sock.on 'error', end

      debug "Repl #{sock.id} has started"

    onListening = => debug "ClusterMaster repl listening on #{@address}"

    if @address.port?
      server.listen @address.port, @address.address, onListening
    else
      server.listen @address.address, onListening

    return

  stop: ->

