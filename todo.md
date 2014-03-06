# Bug when process is repeatedly failing

if a previous restart is failing repeatedly and an update is called, the program always dies just after/before the successful child fork:

    stdin:9561: WARNING - Suspicious code. This code lacks side-effects. Is there a bug?
    Browser__1012, Registry__691 = Browser__1012.Registry, queue__703 = Browser__1012.queue,
    ^

    0 error(s), 17 warning(s)


    Thu, 06 Mar 2014 21:22:36 GMT cluster-master Restarting with node path [/opt/node/bin/node]
    Thu, 06 Mar 2014 21:22:36 GMT cluster-master Restart: forking first
    Thu, 06 Mar 2014 21:22:36 GMT cluster-master Worker 37 (27383) starting
    Error: ENOENT, no such file or directory '1.pem'
      at Object.fs.openSync (fs.js:427:18)
      at Object.fs.readFileSync (fs.js:284:15)
      at readCertificateChain (/home/mikerobe/Server/node/staging/2014-03-06-1394140765/bin/serve.coffee:34:6)
      at Object.<anonymous> (/home/mikerobe/Server/node/staging/2014-03-06-1394140765/bin/serve.coffee:43:6)
      at Object.<anonymous> (/home/mikerobe/Server/node/staging/2014-03-06-1394140765/bin/serve.coffee:4:1)
      at Module._compile (module.js:456:26)

    Thu, 06 Mar 2014 21:22:37 GMT cluster-master Worker 36 (27381) exited abnormally
    Thu, 06 Mar 2014 21:22:37 GMT cluster-master Worker 36 (27381) died too quickly. Entering 'danger mode.'
    connect.multipart() will be removed in connect 3.0
    visit https://github.com/senchalabs/connect/wiki/Connect-3.0 for alternatives
    connect.limit() will be removed in connect 3.0
    Warning: connection.session() MemoryStore is not
    designed for a production environment, as it will leak
    memory, and will not scale past a single process.
    Uncaught exception:  [TypeError: Cannot read property 'id' of undefined] TypeError: Cannot read property 'id' of undefined
      at [object Object]._onTimeout (/home/mikerobe/Server/node/staging/node_modules/cluster-master/lib/cluster-master.coffee:183:69)
      at Timer.listOnTimeout [as ontimeout] (timers.js:110:15)

    Thu, 06 Mar 2014 21:22:38 GMT cluster-master Forceful shutdown
    ^CShared connection to 208.94.241.90 closed.
