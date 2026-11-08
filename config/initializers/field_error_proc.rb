# Fields with a validation error keep Rails' wrapper (styled in application.css) and are also marked
# aria-invalid, so screen readers say which field needs fixing, not only the summary at the top.
ActionView::Base.field_error_proc = proc do |html_tag, _instance|
  tag = html_tag.to_s
  tag = tag.sub(/\A<(input|select|textarea)\b/) { "<#{$1} aria-invalid=\"true\"" } unless tag.include?("aria-invalid")
  %(<div class="field_with_errors">#{tag}</div>).html_safe
end
