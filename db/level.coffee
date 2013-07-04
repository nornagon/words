level = require 'level'

db = level 'text', valueEncoding: 'json'

reindex = (callback) ->
  ws = db.createWriteStream type:'del'
  rs = db.createReadStream start:'idx/', end:'idx/~', valueEncoding:'utf8'
  rs.pipe(ws).on 'close', ->
    rs = db.createValueStream start:'posts/', end:'posts/~'
    batch = db.batch()

    rs.on 'data', (d) -> indexPost d, batch
    rs.on 'close', ->
      console.log 'reindexed'
      batch.write callback

indexPost = (post, batch) ->
  batch.put "idx/by_date/#{post.created_at}", post.slug, valueEncoding:'utf8'

  if post.published
    batch.put "idx/published/#{post.created_at}", post.slug, valueEncoding:'utf8'
  else
    batch.del "idx/published/#{post.created_at}"

deIndex = (post, batch) ->
  batch.del "idx/by_date/#{post.created_at}"
  if post.published
    batch.del "idx/published/#{post.created_at}"


#reindex()

exports.getPostsByDate = (cb) ->
  getPosts 'idx/by_date/', cb

exports.getPublishedPosts = (limit, cb) ->
  getPosts 'idx/published/', {limit, reverse:yes}, cb

getPosts = (path, opts, callback) ->
  [opts, callback] = [{}, opts] if typeof opts is 'function'

  if opts.reverse
    opts.start = path + '~'
    opts.end = path
  else
    opts.start = path
    opts.end = path + '~'

  opts.keys = no
  opts.valueEncoding = 'utf8'

  # Published posts are indexed by creation time.
  rs = db.createValueStream opts

  docs = []
  tasks = 0
  idx = 0

  doneTask = ->
    tasks++
    if tasks == docs.length + 1
      callback null, docs

  rs.on 'data', (slug) ->
    i = idx++
    db.get "posts/#{slug}", (err, data) ->
      #console.log 'getposts', err, data
      docs[i] = data
      doneTask()

  rs.on 'close', doneTask

exports.putPost = (post, callback) ->
  batch = db.batch().put "posts/#{post.slug}", post
  indexPost post, batch
  batch.write callback

exports.delPost = (slug, callback) ->
  db.get "posts/#{slug}", (err, post) ->
    batch = db.batch().del "posts/#{slug}"
    deIndex post, batch
    batch.write (err) ->
      #console.log 'deindex err', err
      callback err

exports.getPostBySlug = (slug, cb) -> db.get "posts/#{slug}", cb
