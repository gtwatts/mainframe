# Sample Ruby file for symbol extraction tests

module Authentication
  class Authenticator
    attr_accessor :token, :expiry
    attr_reader :user_id

    def initialize(user_id)
      @user_id = user_id
      @token = nil
    end

    def authenticate(password)
      validate_password(password)
    end

    def refresh_token
      @token = generate_token
    end

    private

    def validate_password(password)
      password.length >= 8
    end

    def generate_token
      SecureRandom.hex(32)
    end
  end

  class TokenStore
    def initialize
      @store = {}
    end

    def save(key, token)
      @store[key] = token
    end
  end
end

def standalone_helper(value)
  value.to_s.strip
end
