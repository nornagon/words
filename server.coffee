express = require 'express'
cradle = require 'cradle'
events = require 'events'
request = require 'request'

OWNER = "nornagon@nornagon.net"

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

app.engine 'html', require('consolidate').toffee
app.set 'view engine', 'html'
app.set 'views', __dirname + '/views'

app.use express.logger()
app.use express.static __dirname + '/static'
app.use express.cookieParser 'asfasd;kghrgwtiug52bgy524oybg24v5 248 tv2o3qdhaliwencwqj-erv0t2'
app.use express.session()
app.use express.bodyParser()
#app.use express.csrf()

# Middleware to make sure a user is logged in before allowing them to access the page.
# You could improve this by setting a redirect URL to the login page, and then redirecting back
# after they've authenticated.
restrict = (req, res, next) ->
  return next() if req.session.user
  res.redirect '/login'

app.post '/auth', (req, res, next) ->
  return next(new Error 'No assertion in body') unless req.body.assertion

  # Persona has given us an assertion, which needs to be verified. The easiest way to verify it
  # is to get mozilla's public verification service to do it.
  #
  # The audience field is hardcoded, and does not use the HTTP headers or anything. See:
  # https://developer.mozilla.org/en-US/docs/Persona/Security_Considerations
  request.post 'https://verifier.login.persona.org/verify'
    form:
      audience:"localhost:#{port}"
      assertion:req.body.assertion
    (err, _, body) ->
      return next(err) if err

      try
        data = JSON.parse body
      catch e
        return next(e)

      return next(new Error data.reason) unless data.status is 'okay'

      return next(new Error "Unauthorized user") unless data.email is OWNER

      # Login worked.
      req.session.user = data.email
      res.redirect '/admin'

# We need to do 2 things during logout:
# - Delete the user's logged in status from their session object (ie, record they've been
#   logged out on the server)
# - Tell persona they've been logged out in the browser.
app.get '/logout', restrict, (req, res, next) ->
  res.render 'logout', user: req.session.user
  delete req.session.user

# The login page needs CSRF (cross-site request forging) protection. The token is generated by
# the express.csrf() middleware, its injected into the hidden login form and then automatically
# checked when the login form is submitted.
app.get '/login', (req, res) ->
  res.render 'login', csrf:req.session._csrf, user:req.session.user



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


app.get '/admin', restrict, (req, res) ->
  db.view 'posts/by_date', { include_docs: true }, (err, posts) ->
    posts.reverse()
    res.setHeader 'cache-control', 'no-store'
    res.render 'admin',
      user: req.session.user
      slugFromTitle: slugFromTitle.toString()
      ideas: (p.doc for p in posts when !p.doc.published)
      published: (p.doc for p in posts when p.doc.published)

app.post '/api/add', restrict, (req, res) ->
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

app.post '/api/update', restrict, (req, res) ->
  complete req, (buf) ->
    data = JSON.parse(buf)
    db.get data.id, (err, r) ->
      throw err if err
      for k,v of data.update when k in ['title', 'body']
        r[k] = v
      db.save r._id, r._rev, r, (err, r) ->
        throw err if err
        res.end JSON.stringify ok: yes

app.post '/api/delete', restrict, (req, res) ->
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
      opts.model = p
    p.body = md.makeHtml p.body
    opts.post = p
    res.render 'text', opts

app.get '/:slug', (req, res) ->
  renderPost req, res

app.get '/:slug/edit', restrict, (req, res) ->
  renderPost req, res, model: true

port = process.argv[2] ? 8000
app.listen port
console.log "Listening on http://localhost:#{port}"
