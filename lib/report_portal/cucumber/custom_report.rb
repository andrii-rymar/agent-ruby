require 'cucumber/formatter/ansicolor'

require_relative 'messagesreport'

module ReportPortal
  module Cucumber
    class CustomReport < MessagesReport
      def test_step_started(event, desired_time = ReportPortal.now)
      end

      def test_step_finished(event, desired_time = ReportPortal.now)
        test_step = event.test_step
        result = event.result
        status = result.to_sym

        if step?(test_step) # `after_test_step` is also invoked for hooks
          step_source = @ast_lookup.step_source(test_step).step
          message = "#{step_source.keyword}#{step_source.text}"
          if test_step.multiline_arg.doc_string?
            message << %(\n"""\n#{test_step.multiline_arg.content}\n""")
          elsif test_step.multiline_arg.data_table?
            message << test_step.multiline_arg.raw.reduce("\n") { |acc, row| acc << "| #{row.join(' | ')} |\n" }
          end

          color_message = color_message(message, color_for_status(status))
          ReportPortal.send_log(:info, color_message, time_to_send(desired_time))
        end

        if %i[failed pending undefined].include?(status)
          exception_info = if %i[failed pending].include?(status)
                             ex = result.exception
                             format("%s: %s\n  %s", ex.class.name, ex.message, ex.backtrace.join("\n  "))
                           else
                             format("Undefined step: %s:\n%s", test_step.text, test_step.source.last.backtrace_line)
                           end
          ReportPortal.send_log(:error, exception_info, time_to_send(desired_time))
        end

        if status != :passed
          log_level = status == :skipped ? :warn : :error
          step_type = if step?(test_step)
                        'Step'
                      else
                        # TODO: Find out what this looks like in Cucumber3, to try and track down
                        # how we ought to behave
                        hook_class_name = test_step.text
                        location = test_step.location.to_s
                        "#{hook_class_name} at `#{location}`"
                      end
          ReportPortal.send_log(log_level, "#{step_type} #{status}", time_to_send(desired_time))
        end
      end

      private

      def start_feature_with_parentage(gherkin_source, desired_time)
        parent_node = @root_node
        child_node = nil
        feature = gherkin_source.feature
        path_components = gherkin_source.uri.split(File::SEPARATOR)
        path_components.each_with_index do |path_component, index|
          child_node = parent_node[path_component]
          unless child_node # if child node was not created yet
            if index < path_components.size - 1
              name = "Folder: #{path_component}"
              description = nil
              tags = []
              type = :SUITE
            else
              name = "#{feature.keyword}: #{feature.name}"
              description = gherkin_source.uri # TODO: consider adding feature description and comments
              tags = feature.tags.map(&:name)
              type = :TEST
            end
            # TODO: multithreading # Parallel formatter always executes scenarios inside the same feature in the same process
            if (parallel? || attach_to_launch?) &&
              index < path_components.size - 1 && # is folder?
              (id_of_created_item = ReportPortal.uuid_of(name, parent_node)) # get id for folder from report portal
              # get child id from other process
              item = ReportPortal::TestItem.new(name: name, type: type, id: id_of_created_item, start_time: time_to_send(desired_time), description: description, closed: false, tags: tags)
              child_node = Tree::TreeNode.new(path_component, item)
              parent_node << child_node
            else
              item = ReportPortal::TestItem.new(name: name, type: type, id: nil, start_time: time_to_send(desired_time), description: description, closed: false, tags: tags)
              child_node = Tree::TreeNode.new(path_component, item)
              parent_node << child_node
              item.id = ReportPortal.start_item(child_node) # TODO: multithreading
            end
          end
          parent_node = child_node
        end
        @parent_item_node = child_node
      end

      def color_for_status(status)
        ::Cucumber::Formatter::ANSIColor::ALIASES[status.to_s]
      end

      def color_message(message, color)
        %(<span style="color:#{color}">#{message}</span>)
      end
    end
  end
end
