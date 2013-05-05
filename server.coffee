express = require 'express'
cradle = require 'cradle'
events = require 'events'

couch = new (cradle.Connection)('http://localhost', 5984, {
	cache: false,
	raw: false,
})
db = couch.database('text')
db.exists (err, exists) ->
  throw err if err
  if not exists
    db.create()
  require('./views').push(db)

app = express()

app.engine 'html', require('consolidate').mustache
app.set 'view engine', 'html'
app.set 'views', __dirname + '/views'

app.use express.logger()
app.use express.static __dirname + '/static'

complete = (req, cb) ->
  buffer = new Buffer 0
  ee = new events.EventEmitter
  req.on 'data', (data) ->
    newBuffer = new Buffer(buffer.length + data.length)
    buffer.copy newBuffer
    data.copy newBuffer, buffer.length
    buffer = newBuffer
  req.on 'end', ->
    cb? buffer
    ee.emit 'complete', buffer
  ee

slugFromTitle = (title) ->
  title.toLowerCase().replace(/[^a-z]+/g, '-').substr(0,25).replace(/-$/,'')

app.get '/', (req, res) ->
  db.view 'posts/by_date', { include_docs: true }, (err, posts) ->
    posts.reverse()
    res.setHeader 'cache-control', 'no-store'
    res.render 'index',
      slugFromTitle: slugFromTitle.toString()
      ideas: (p.doc for p in posts when !p.doc.published)
      published: (p.doc for p in posts when p.doc.published)

app.post '/api/add', (req, res) ->
  complete req, (buf) ->
    data = JSON.parse(buf)
    post =
      type: 'post'
      title: data.title
      body: data.body ? ''
      published: data.published ? false
      created_at: (new Date).toISOString()
      slug: data.slug ? slugFromTitle(data.title)
    db.save post, (err, r) ->
      if err
        return res.end JSON.stringify ok: no, err: err
      res.end JSON.stringify ok: yes

app.post '/api/update', (req, res) ->
  complete req, (buf) ->
    data = JSON.parse(buf)
    db.get data.id, (err, r) ->
      throw err if err
      console.log r, data
      for k,v of data.update when k in ['title', 'body']
        r[k] = v
      db.save r._id, r._rev, r, (err, r) ->
        throw err if err
        console.log r
        res.end JSON.stringify ok: yes

app.post '/api/delete', (req, res) ->
  complete req, (buf) ->
    data = JSON.parse buf
    getPostBySlug data.slug, (err, posts) ->
      if posts.length <= 0
        # TODO 404
        return res.end()
      p = posts[0]
      db.remove p.id, p.doc._rev, (err, r) ->
        if err
          return res.end JSON.stringify ok: no, err: err
        res.end JSON.stringify ok: yes

getPostBySlug = (slug, cb) ->
  db.view 'posts/by_slug', {
    include_docs: true
    startkey: slug
    endkey: slug
  }, cb

pd = require 'pagedown'
md = new pd.Converter
renderPost = (req, res, opts = {}) ->
  getPostBySlug req.params.slug, (err, posts) ->
    if posts.length <= 0
      # TODO 404
      res.end()
      return
    p = posts[0].doc
    if opts.model
      opts.model = JSON.stringify p
    p.body = md.makeHtml p.body
    opts.post = p
    res.render 'text', opts

app.get '/:slug', (req, res) ->
  renderPost req, res

app.get '/:slug/edit', (req, res) ->
  renderPost req, res, model: true

app.listen 3000
console.log "Listening on http://localhost:3000"
