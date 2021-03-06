# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'bcrypt'
require_relative '../lib/routes'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def session
    last_request.env['rack.session']
  end

  def admin_session
    { 'rack.session' => { login: 'success' } }
  end

  def test_index_logged_out
    get '/'

    assert_equal(302, last_response.status)
    assert_equal('You need to be logged in to do that.', session[:message])
  end

  def test_index_logged_in
    get '/', {}, admin_session

    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    refute_nil(session[:login])
    assert_includes(last_response.body, "Signed in as #{session[:username]}")
  end

  def test_login_page_view
    get '/users/login'

    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, '<form')
    refute_includes(last_response.body, 'Signed in as')
  end

  def test_login_valid
    post '/users/login', { username: 'admin', password: 'secret' }

    assert_equal(302, last_response.status)
    assert_equal('success', session[:login])
  end

  def test_login_invalid
    post '/users/login', { username: 'random_string', password: 'some_pass' }

    assert_equal(422, last_response.status)
    # Can't access the session[:message] after re-render due to delete method
    assert_includes(last_response.body, 'Incorrect login details; please try again')
  end

  def test_logout
    post '/users/logout'

    assert_equal(302, last_response.status)
    assert_equal(session[:message], 'You have been logged out.')
    assert_nil(session[:username])
  end

  def test_create_contact_view
    get '/new', {}, admin_session

    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, "New contact")
  end

  def test_create_valid_contact
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Lazy Boyz' }

    assert_equal(302, last_response.status)
    assert_instance_of(Book, session[:contact_list])
    assert_equal('Albert', session[:contact_list].display_contacts[0][:details][:name])

    get '/'

    assert_includes(last_response.body, 'Name: Albert')
    assert_includes(last_response.body, 'Phone Number: 0421345678')
  end

  def test_create_multiple_valid_contact
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog',
           categories: 'Lazy Boyz, Cool Kids' }

    assert_equal(302, last_response.status)
    assert_instance_of(Book, session[:contact_list])
    assert_equal('Albert', session[:contact_list].display_contacts[0][:details][:name])

    post '/new', { name: 'Yimby', phone_num: '0421345679', address: '125 Lazy St, The Bog', categories: 'Lazy Boyz' }

    assert_equal(302, last_response.status)
    assert_instance_of(Book, session[:contact_list])
    assert_equal('Yimby', session[:contact_list].display_contacts[1][:details][:name])

    get '/'

    assert_includes(last_response.body, 'Name: Albert')
    assert_includes(last_response.body, 'Name: Yimby')
    assert_includes(last_response.body, 'Phone Number: 0421345678')
    assert_includes(last_response.body, 'Phone Number: 0421345679')
    assert_includes(last_response.body, 'Category: Lazy Boyz,  Cool Kids')
  end

  def test_create_invalid_contact
    get '/', {}, admin_session
    post '/new', { name: 'Albert', phone_num: '042135678', address: '123 Lazy St, The Bog', categories: 'Lazy Boyz' }

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Invalid field detected!')

    post '/new', { name: 'Albert', phone_num: '0421356788', address: '1', categories: 'Lazy Boyz' }

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Invalid field detected!')
  end

  def test_delete_contact
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog',
           categories: 'Lazy Boyz, Cool Kids' }
    post '/new',
         { name: 'Crimbolio', phone_num: '0421345678', address: '123 Lazy St, The Bog',
           categories: 'Lazy Boyz, Cool Kids' }

    post '/1/delete'

    assert_equal(302, last_response.status)
    assert_equal(1, session[:contact_list].display_contacts.size)
    assert_equal('Crimbolio deleted from contacts.', session[:message])
  end

  def test_valid_search
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }
    post '/new',
         { name: 'Crimbolio', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Lazy Boyz' }
    post '/search', { search_name: 'boyz' }

    assert_equal(200, last_response.status)
    assert_includes(last_response.body, 'Boyz')
    refute_includes(last_response.body, 'Cool Kids')
  end

  def test_invalid_search
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }
    post '/search', { search_name: 'boyz' }

    assert_equal(302, last_response.status)
    assert_includes(session[:message], "The 'boyz' search term was not found.")
    refute_includes(last_response.body, 'boyz')
  end

  def test_edit_page_view
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }
    get '/0/edit'

    assert_equal(200, last_response.status)
    assert_equal('text/html;charset=utf-8', last_response['Content-Type'])
    assert_includes(last_response.body, "Edit contact")
  end

  def test_edit_page_view_invalid
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }
    get '/hello/edit'

    assert_equal(302, last_response.status)
    assert_equal('Invalid contact. Please check and try again.', session[:message])
    assert_equal('Albert', session[:contact_list].display_contacts[0][:details][:name])
  end

  def test_invalid_edit_field
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }
    post '/0/edit',
         { name: 'Albort', phone_num: '04219', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }

    assert_equal(422, last_response.status)
    assert_includes(last_response.body, 'Invalid field detected! Please check and try again.')
    assert_equal('Albert', session[:contact_list].display_contacts[0][:details][:name])
  end

  def test_valid_edit
    get '/', {}, admin_session
    post '/new',
         { name: 'Albert', phone_num: '0421345678', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }
    post '/0/edit',
         { name: 'Albort', phone_num: '0421345679', address: '123 Lazy St, The Bog', categories: 'Cool Kids' }
    
    assert_equal(302, last_response.status)
    assert_equal('Contact for Albort successfully updated.', session[:message])
    assert_equal('Albort', session[:contact_list].display_contacts[0][:details][:name])
    assert_equal('0421345679', session[:contact_list].display_contacts[0][:details][:phone_number])
  end

  def test_redirects
    get '/random_link', {}, admin_session

    assert_equal(302, last_response.status)
    assert_equal('That page was not found!', session[:message])
  end
end
