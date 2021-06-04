ENV["RACK_ENV"] = "test"

require 'minitest/autorun'
require 'rack/test'

require_relative "../cms.rb"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    credentials = { "admin" => "$2a$12$E3E5OTHyEad/W5wQKliBVu0L4x1nxla7qECKlGeygknpyi4YmBslq" }
    write_new_credentials(credentials, true)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content="")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_history_doc
    create_document "about.md", "open source programming language"

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "open source programming language"
  end

  def test_document_not_found
    get "/notafile.ext"

    assert_equal 302, last_response.status
    assert_equal "notafile.ext does not exist.", session[:message]
  end

  def test_viewing_markdown_document
    create_document "about.md", "<h1>Ruby is...</h1>"

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_editing_document
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_updating_document
    post "/changes.txt", {content: "new content" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_view_new_document_form
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add a new document:"
    assert_includes last_response.body, %q(<form action="/create")
  end

  def test_create_new_document
    post "/create", { filename: "test_doc.txt" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "test_doc.txt was created.", session[:message]

    get "/"
    assert_includes last_response.body, "test_doc.txt"
  end

  def test_error_creating_new_document_no_filename
    post "/create", { filename: "" }, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required"
  end

  def test_delete_file
    create_document "test_file.txt"

    post "/test_file.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test_file.txt has been deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/test_file.txt")
  end

  def test_view_signin_page
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<form action="/users/signin")
  end

  def test_valid_signin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "admin", session[:username]
    assert_equal "Welcome!", session[:message]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_invalid_signin
    post "/users/signin", username: "bob", password: "sauce"

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid credentials"
    assert_nil session[:username]
  end

  def test_signout
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign In"
  end

  def test_guest_redirect_from_edit
    create_document("test.txt")

    get "/test.txt/edit"
    assert_equal "You must be signed in to do that.", session[:message]

    get "/"
    assert_nil session[:message]

    post "/test.txt"
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_guest_redirect_from_new
    create_document("test.txt")

    get "/new"
    assert_equal "You must be signed in to do that.", session[:message]

    get "/"
    assert_nil session[:message]

    post "/create"
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_guest_redirect_from_delete
    create_document("test.txt")

    post "/test.txt/delete"
    assert_equal "You must be signed in to do that.", session[:message]

    get "/"
    assert_nil session[:message]
  end

  def test_invalid_file_name
    post "/create", { filename: "bad.pdf" }, admin_session
    assert_includes last_response.body, "Only #{VALID_FILE_EXTENSIONS.join(", ")} files are accepted."
    assert_equal 422, last_response.status

    get "/"
    refute_includes last_response.body, "bad.pdf"
  end

  def test_duplicate_file
    create_document("test.txt", "my awesome content")

    post "/clone", { filename: "test.txt" }, admin_session

    get "/"
    assert_includes last_response.body, "test.txt was duplicated."
    assert_includes last_response.body, "test(copy).txt"

    get "/test.txt"
    assert_includes last_response.body, "my awesome content"
  end

  def test_guest_redirect_from_duplicate
    create_document("test.txt")

    post "/clone", filename: "test.txt"
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_signup_page
    get "/"
    assert_includes last_response.body, "Sign Up"

    get "/users/signup"
    assert_includes last_response.body, "Create a new username and password:"
  end

  def test_signup_new_user
    post "/users/signup", username: "new_user", password: "secret"

    get "/"
    assert_includes last_response.body, "Your account has been created. Welcome!"
    assert_includes last_response.body, "Signed in as new_user"

    post "/users/signout"

    post "/users/signin", username: "new_user", password: "secret"

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as new_user"
  end

  def test_reject_new_signup_if_username_exists
    post "/users/signup", username: "admin", password: "something"
    assert_includes last_response.body, "That username is taken. Please choose a new one."
  end

  def test_reject_new_signup_invalid_username
    post "/users/signup", username: "bo", password: "something"
    assert_includes last_response.body, "Username must be 3-20 characters (letters, numbers, & underscores only)"

    post "/users/signup", username: "$$$", password: "something"
    assert_includes last_response.body, "Username must be 3-20 characters (letters, numbers, & underscores only)"
  end
end
