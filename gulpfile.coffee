gulp = require 'gulp'
browserify = require 'browserify'
coffeeify = require 'caching-coffeeify'
through2 = require 'through2'
rename = require 'gulp-rename'
mocha = require 'gulp-spawn-mocha'
docco = require 'gulp-docco'
sourcemaps = require 'gulp-sourcemaps'
uglify = require 'gulp-uglify'

DEBUG = (process.env.NODE_ENV is 'debug')

gulp.task 'compile', ->
  browserified = through2.obj (file, enc, next) ->
    browserify(file.path, {standalone: 'stats', debug: true})
        .transform(coffeeify)
        .bundle (err, res) ->
          if err?
            return next err

          file.contents = res
          next null, file

  gulp.src('src/main.coffee')
      .pipe(browserified)
      .pipe(sourcemaps.init({loadMaps: true}))
      .pipe(rename 'main.js')
      .pipe(sourcemaps.write '.')
      .pipe(gulp.dest './build/')

gulp.task 'test', ->
  gulp.src(['test/*.coffee'])
      .pipe(mocha({
        debugBrk: DEBUG
        reporter: 'spec'
        compilers: 'coffee:coffee-script'
      }))

gulp.task 'default', ['compile', 'test']
gulp.task 'all', ['docs', 'compile', 'test']
