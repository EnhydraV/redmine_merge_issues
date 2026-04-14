# config/routes.rb

RedmineApp::Application.routes.draw do
  # Nested under /issues/:issue_id/merge
  resources :issues, only: [] do
    resource :merge,
             controller: 'merge_issues',
             only: [:new, :create],
             as: :merge
  end
end
