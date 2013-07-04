cradle = require 'cradle'
couch = new cradle.Connection 'http://localhost', 5984, {
  cache: false
  raw: false
}

designs =
  posts:
    by_date: (doc) ->
      if doc.type is 'post'
        emit doc.created_at, null
    by_slug: (doc) ->
      if doc.type is 'post'
        emit doc.slug, null
    published: (doc) ->
      if doc.type is 'post' and doc.published
        emit doc.created_at, null

pushDesigns = (db) ->
	for d of designs
		do (d) ->
      for v of designs[d]
        if typeof designs[d][v] is 'function'
          designs[d][v] = { map: designs[d][v] }
      db.get '_design/' + d, (err, res) ->
        # if (err) { console.log(err); return }
        data = JSON.stringify designs[d], (k, val) ->
          if typeof val is 'function'
            val.toString()
          else
            val
        if res and data == JSON.stringify(res.views)
          #console.info("_design/" + d + " up to date (rev " + res._rev + ")")
        else
          db.save '_design/' + d, designs[d], (err, res) ->
            throw err if err
            console.info "Updated " + res.id + " (rev " + res.rev + ")"

db = couch.database('text')
db.exists (err, exists) ->
  throw err if err
  if not exists
    db.create()
  pushDesigns db

exports.getPostsByDate = (cb) ->
  db.view 'posts/by_date', {
    include_docs: true
    descending: true
  }, (err, posts) ->
    return cb err if err
    cb null, (p.doc for p in posts)

exports.putPost = (post, cb) ->
  db.save post, (err, r) ->
    return cb err if err
    cb null, r

getDocBySlug = (slug, cb) ->
  db.view 'posts/by_slug', {
    include_docs: true
    startkey: slug
    endkey: slug
  }, (err, posts) ->
    return cb err if err
    if posts.length <= 0
      return cb new Error('post not found')
    cb null, posts[0]

exports.getPostBySlug = (slug, cb) ->
  getDocBySlug slug, (err, r) ->
    return cb err if err
    cb null, r.doc

exports.delPost = (slug, cb) ->
  getDocBySlug slug, (err, p) ->
    return cb err if err
    db.remove p.id, p.doc._rev, (err, r) ->
      return cb err if err
      cb null, r

exports.getPublishedPosts = (limit, cb) ->
  db.view 'posts/published', {
    include_docs: true
    descending: true
    limit: 10
  }, (err, posts) ->
    return cb err if err
    cb null, (p.doc for p in posts)
