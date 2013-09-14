class TodoItemController < ApplicationController
  unloadable

  before_filter :find_todo_list, :only => :create
  before_filter :find_todo_item, :only => [:toggle, :update, :delete]
  before_filter :find_project

  def create
    (render_403; return false) unless User.current.allowed_to?(:create_todos, @project)

    settings = Setting[:plugin_redmine_todos]

    @issue = Issue.new(
        :author_id=>User.current.id,
        :subject=>params[:subject_new],
        :status_id=>settings[:uncompleted_todo_status],
        :assigned_to_id => User.current.id,
        :due_date => params[:due_date_new],
        :assigned_to_id => params[:assigned_to_id_new]
    )
    @issue.project = @project
    @issue.tracker ||= @project.trackers.find((params && params[:tracker_id]) || params[:tracker_id] || :first)
    if @issue.tracker.nil?
      render_error l(:error_no_tracker_in_project)
      return false
    end

    todo_item = TodoItem.new(:todo_list_id=> @todo_list.id)
    success = self.do_save(todo_item, @issue)
    render :json => {:success => success}.merge(todo_item.as_json)
  end

  def update
    (render_403; return false) unless User.current.allowed_to?(:update_todos, @project)
    if params[:saveMode]
      if params[:saveMode] == "name"
        @todo_item.issue.subject = params[:subject_new]
      elsif params[:saveMode] == "due_assignee"
        if params.include? :assigned_to_id_new
          @todo_item.issue.assigned_to_id = params[:assigned_to_id_new]
        end
        if params.include? :due_date_new
          @todo_item.issue.due_date = params[:due_date_new] ? Time.parse(params[:due_date_new]) : nil
        end
      end
    end
    return render :json => {:success => self.do_save(@todo_item)}.merge(@todo_item.as_json).to_json
  end

  def delete
    (render_403; return false) unless User.current.allowed_to?(:delete_todos, @project)
    @todo_item.issue.delete()
    @todo_item.delete()
    return render :json => {:success => true}.to_json
  end

  def toggle
    (render_403; return false) unless User.current.allowed_to?(:update_todos, @project)

    settings = Setting[:plugin_redmine_todos]
    @todo_item.issue.status_id = params[:completed] ? settings[:completed_todo_status] : settings[:uncompleted_todo_status]
    @todo_item.completed_at = params[:completed] ? Time.now : nil
    return render :json => {:success => self.do_save(@todo_item), :completed_at => @todo_item.completed_at }.to_json
  end

  protected

  def do_save(todo_item, issue=nil)
    issue ||= todo_item.issue
    Issue.transaction do
      TodoItem.transaction do
        call_hook(:controller_issues_new_before_save, { :params => params, :issue => todo_item.issue })
        if issue.save!
          call_hook(:controller_issues_new_after_save,  { :params => params, :issue => todo_item.issue})
          if todo_item.id.nil?
            todo_item.issue_id = issue.id
          end
          todo_item.issue = issue
          if todo_item.save!
            return true
          end
        end
      end
    end
    return false
  end

  def find_todo_list
    @todo_list = TodoList.find(params[:todo_list_id])
  end

  def find_todo_item
    @todo_item = TodoItem.includes(:issue).find(params[:id])
  end

  # This is actually not the same as in the parent class - we are looking for :project_id instead of :id
  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

end

