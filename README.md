[![Gem Version](https://badge.fury.io/rb/gemstar.svg)](https://rubygems.org/gems/gemstar)
[![Build](https://github.com/FDj/gemstar/workflows/Build/badge.svg)](https://github.com/palkan/gemstar/actions)
[![JRuby Build](https://github.com/FDj/gemstar/workflows/JRuby%20Build/badge.svg)](https://github.com/FDj/gemstar/actions)

# Gemstar
A very preliminary gem to help you keep track of your gems.

## Installation

Until it's released on RubyGems, you can install it from GitHub:

```shell
# Shell
gem install specific_install
gem specific_install -l https://github.com/FDj/gemstar.git
```

Or adding to your project:

```ruby
# Gemfile
group :development do
  gem "gemstar", github: "FDj/gemstar"
end
```

## Usage

### `gemstar diff`

Run this after you've updated your gems.

```shell
# in your project directory:
bundle exec gemstar diff
```

This will generate an html diff report with changelog entries for each gem that was updated:

![Gemstar diff command output](docs/diff.png)

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/FDj/gemstar](https://github.com/FDj/gemstar).

## Credits

This gem is generated via [`newgem` template](https://github.com/palkan/newgem) by [@palkan](https://github.com/palkan).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
