fs = require 'fs'
express = require 'express'
events = require 'events'
request = require 'request'
marked = require 'marked'

hljs = require('highlight.js')
marked.setOptions highlight: (code, lang) ->
  # If the language is wacky, this throws.
  try
    if lang
      hljs.highlight(lang, code).value
    else
      hljs.highlightAuto(code).value
  catch
    code

config_defaults =
  title: 'profound and witty blog title'
  email: 'you@your.domain'
  name: 'Super Cool Guy'
  db: 'level'
  secret: require('crypto').randomBytes(64).toString()
  badge: '*'

config = try
  JSON.parse fs.readFileSync './config.json'
catch e
  {}
config.__proto__ = config_defaults

db = require "./db/#{config.db}"

app = express()

app.engine 'html', require('consolidate').toffee
app.set 'view engine', 'html'
app.set 'views', __dirname + '/views'

app.use express.logger 'dev'
app.use express.static __dirname + '/static'
app.use express.static __dirname + '/node_modules/marked/lib'
app.use express.bodyParser()
app.use express.cookieParser()

#app.use express.session()
#app.use express.csrf()
session = express.cookieSession secret:config.secret, proxy:true
app.use app.router


# Middleware to make sure a user is logged in before allowing them to access the page.
# You could improve this by setting a redirect URL to the login page, and then redirecting back
# after they've authenticated.
restrict = (req, res, next) ->
  return next() if req.session.user
  res.redirect '/login'

app.post '/auth', session, (req, res, next) ->
  return next(new Error 'No assertion in body') unless req.body.assertion

  # Persona has given us an assertion, which needs to be verified. The easiest way to verify it
  # is to get mozilla's public verification service to do it.
  #
  # The audience field is hardcoded, and does not use the HTTP headers or anything. See:
  # https://developer.mozilla.org/en-US/docs/Persona/Security_Considerations
  request.post 'https://verifier.login.persona.org/verify',
    form:
      audience:req.headers.host
      assertion:req.body.assertion
    (err, _, body) ->
      return next(err) if err

      try
        data = JSON.parse body
      catch e
        return next(e)

      return next(new Error data.reason) unless data.status is 'okay'

      return next(new Error "Unauthorized user") unless data.email is config.email

      # Login worked.
      req.session.user = data.email
      res.redirect '/admin'

# We need to do 2 things during logout:
# - Delete the user's logged in status from their session object (ie, record they've been
#   logged out on the server)
# - Tell persona they've been logged out in the browser.
app.get '/logout', session, (req, res, next) ->
  res.render 'logout', user: req.session?.user
  delete req.session.user if req.session
  req.session = null

# The login page needs CSRF (cross-site request forging) protection. The token is generated by
# the express.csrf() middleware, its injected into the hidden login form and then automatically
# checked when the login form is submitted.
app.get '/login', session, (req, res) ->
  res.render 'login', csrf:req.session._csrf, user:req.session.user

slugFromTitle = (title) ->
  title.toLowerCase().replace(/[^a-z]+/g, '-').substr(0,25).replace(/-$/,'')

app.get '/admin', session, restrict, (req, res) ->
  db.getPostsByDate (err, posts) ->
    res.setHeader 'cache-control', 'no-store'
    res.render 'admin',
      config: config
      user: req.session.user
      slugFromTitle: slugFromTitle.toString()
      ideas: (p for p in posts when !p.published)
      published: (p for p in posts when p.published)

app.post '/api/add', session, restrict, (req, res) ->
  data = req.body
  post =
    type: 'post'
    title: data.title
    body: data.body ? ''
    published: data.published ? false
    created_at: (new Date).toISOString()
    slug: data.slug ? slugFromTitle(data.title)
  db.putPost post, (err) ->
    return res.json 500, ok: no, err: err if err
    res.json ok: yes

app.post '/api/delete', session, restrict, (req, res) ->
  db.delPost req.body.slug, (err) ->
    if err
      return res.json 500, ok: no, err: err
    res.json ok: yes

app.post '/api/update', session, restrict, (req, res) ->
  data = req.body
  db.getPostBySlug data.slug, (err, r) ->
    throw err if err
    for k,v of data.update when k in ['title', 'body', 'published']
      r[k] = v
    db.putPost r, (err) ->
      throw err if err
      res.end JSON.stringify ok: yes

renderPost = (req, res, next, opts = {}) ->
  db.getPostBySlug req.params.slug, (err, post) ->
    return next() if !post

    opts.post = post
    opts.model = !!opts.model
    opts.md = marked
    opts.config = config
    res.render 'text', opts

app.get '/', (req, res) ->
  db.getPublishedPosts 10, (err, posts) ->
    res.render 'index', md: marked, posts: posts, config: config

app.get '/:slug', (req, res, next) ->
  renderPost req, res, next

app.get '/:slug/edit', session, restrict, (req, res, next) ->
  renderPost req, res, next, model: true

port = process.argv[2] ? 8888
app.listen port
console.log "Listening on http://localhost:#{port}"
