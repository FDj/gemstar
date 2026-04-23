[![Gem Version](https://badge.fury.io/rb/gemstar.svg)](https://rubygems.org/gems/gemstar)
[![Build](https://github.com/FDj/gemstar/workflows/Build/badge.svg)](https://github.com/palkan/gemstar/actions)
[![JRuby Build](https://github.com/FDj/gemstar/workflows/JRuby%20Build/badge.svg)](https://github.com/FDj/gemstar/actions)

# Gemstar
A very preliminary gem to help you keep track of your gems.

## Installation

The easiest way to install gemstar is to use Bundler:

```shell
# Shell
gem install gemstar
```

Alternatively, add it to the development group in your Gemfile:

```
gem "gemstar", group: :development
```

## Usage

### gemstar server

![Gemstar diff command output](docs/server.png)

Start the interactive web UI:

```shell
gemstar server
```

By default, the server listens to http://127.0.0.1:2112/

To open the root page in your browser after startup:

```shell
gemstar server --open
```


### gemstar diff

Run this after you've updated your dependencies.

```shell
# in your project directory, after bundle update:
gemstar diff
```

This will generate an html diff report with changelog entries for each updated package:

![Gemstar diff command output](docs/diff.png)

You can also specify from and to hashes or tags to generate a diff report for a specific range of commits:

```shell
gemstar diff --from 8e3aa96b7027834cdbabc0d8cbd5f9455165e930 --to HEAD
```

To use a time range instead of choosing the starting commit yourself:

```shell
gemstar diff --project ~/Code/my-app --since "3 weeks"
```

To examine a specific Gemfile.lock, pass it like this:

```shell
gemstar diff --lockfile=~/MyProject/Gemfile.lock
```

To diff a project from anywhere, pass the project directory or a supported project file. In project mode, gemstar includes Ruby gems plus JS packages from `importmap.rb` and `package-lock.json` when present:

```shell
gemstar diff --project ~/Code/my-app
```

To filter a project diff down to one ecosystem:

```shell
gemstar diff --project ~/Code/my-app --ecosystem js
gemstar diff --project ~/Code/my-app --ecosystem gems
```

To write markdown instead of html:

```shell
gemstar diff --format markdown
```

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/FDj/gemstar](https://github.com/FDj/gemstar).

## Credits

This gem is generated via [`newgem` template](https://github.com/palkan/newgem) by [@palkan](https://github.com/palkan).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
