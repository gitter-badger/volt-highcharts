if RUBY_PLATFORM == 'opal'

require 'native'
require 'opal-highcharts'

module Highcharts
  class MainController < Volt::ModelController

    attr_reader :chart, :watches, :watch_counts, :reactive

    def index_ready
      set_model
      create_chart
      start_watching
    end

    def before_index_remove
      stop_watching
      update_page
      @chart = nil
    end

    private

    def set_model
      options = attrs.options
      unless options
        raise ArgumentError, 'no options attribute set for :highcharts component'
      end
      # if the options are a Hash then convert to a Volt::Model
      if options.is_a?(Volt::Model)
        @reactive = true
      else
        options = Volt::Model.new(options)
        @reactive = false
      end
      # set controller's model to options, which captures its methods for self
      self.model = options
      debug __method__, __LINE__, "model._id = #{_id}"
    end

    # Create the chart and add it to the page._charts.
    # page._charts ia an array of Volt::Models with an id and a chart attribute.
    # Also set page._chart to the newly (last) created Highcharts::Chart.
    # Also set page._char_id to the id of the new (last) chart.
    def create_chart
      @chart = Highcharts::Chart.new(model.to_h)
      page._charts << {id: _id, chart: @chart}
      page._chart = @chart
      page._chart_id = _id
    end

    # To be reactive we must watch for model changes
    def start_watching
      @watches = []
      @watch_counts = {}
      if reactive
        watch_titles
        watch_series
      end
    end

    def watch_titles
      watches << -> do
        setup_dependencies(_title)
        setup_dependencies(_subtitle)
        log_change "#{self.class.name}##{__method__}:#{__LINE__} : chart.set_title(#{_title.to_h} #{_subtitle.to_h})"
        chart.set_title(_title.to_h, _subtitle.to_h, true) # redraw
      end.watch!
    end

    def watch_series
      @series_size = _series.size
      watches << -> do
        size = _series.size
        if size == @series_size
          _series.each_with_index do |a_series, index|
            watches << -> do
              log_change "@@@  _series[#{index}] changed", a_series
              watches << -> do
                data = a_series._data
                log_change "@@@ _series[#{index}]._data changed", data
                chart.series[index].set_data(data.to_a)
              end.watch!
              watches << -> do
                title = a_series._title
                log_change "@@@ _series[#{index}]._title changed", title
              end.watch!
              watches << -> do
                setup_dependencies(a_series, nest: true, except: [:title, :data])
                log_change "@@@ _series[#{index}] something other than _title or _data changed", nil
                # chart.series[index].update(_series.to_h)
              end
            end.watch!
          end
        else
          log_change "@@@  _series.size changed to ", size
          @series_size = size
          refresh_all_series
        end
      end.watch!
    end

    # Do complete refresh of all series:
    # 1. remove all series from chart with no redraw
    # 2. add all series in model to chart with no redraw
    # 3. redraw chart
    def refresh_all_series
      until chart.series.empty? do
        debug __method__, __LINE__, "chart.series[#{chart.series.size-1}].remove"
        chart.series.last.remove(false)
      end
      _series.each_with_index do |a_series, index|
        debug __method__, __LINE__, "chart.add_series ##{index}"
        chart.add_series(a_series.to_h, false)
      end
      debug __method__, __LINE__, "chart.redraw"
      chart.redraw
    end

    # Force computation dependencies for attributes of a model
    # TODO: must be better or built-in way ??
    def setup_dependencies(model, nest: true, except: [])
      model.attributes.each { |key, val|
        unless except.include?(key)
          debug __method__, __LINE__, "#{model}.send(#{key})"
          model.send :"_#{key}"
        end
        if nest && val.is_a?(Volt::Model)
          setup_dependencies(val, nest: true, except: except)
        end
      }
    end

    def stop_watching
      @watches.each {|w| w.stop}
      @watches = @watch_counts = nil
    end

    def update_page
      debug __method__, _LINE__, Time.now.to_s
      # clear all references to this chart
      i = page._charts.find_index { |e| e._id == _id }
      if i
        deleted = page._charts.delete_at(i)
        debug __method__, __LINE__, "deleted='#{deleted}' page._charts.size=#{page._charts.size}"
        deleted._chart.destroy
        deleted._chart = nil
      end
      if page._chart_id == _id
        last = page._charts.last
        page._chart_id = last ? last._id : nil
        page._chart = last ? last._chart : nil
      end
    end

    def debug(method, line, s)
      Volt.logger.debug "#{self.class.name}##{method}[#{line}] : #{s}"
    end

    def log_change(label, object = 'nil')
      Volt.logger.debug "#{label} : #{object}"
    end

  end
end

end # RUBY_PLATFORM == 'opal'
