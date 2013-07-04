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
  getPosts 'idx/by_date/', null, cb

exports.getPublishedPosts = (limit, cb) ->
  getPosts 'idx/published/', limit, cb

getPosts = (path, limit, callback) ->
  # Published posts are indexed by creation time.
  rs = db.createValueStream
    start: path
    end: path + '~'
    keys: no
    limit: limit
    valueEncoding: 'utf8'

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
