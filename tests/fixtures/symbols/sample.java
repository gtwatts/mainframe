package com.example.app;

import java.util.List;
import java.util.Optional;

public enum Priority {
    LOW,
    MEDIUM,
    HIGH
}

public interface Repository<T> {
    Optional<T> findById(String id);
    List<T> findAll();
    T save(T entity);
    void delete(String id);
}

public class UserService implements Repository<User> {
    private final Database db;

    public UserService(Database db) {
        this.db = db;
    }

    public Optional<User> findById(String id) {
        return db.query(id);
    }

    public List<User> findAll() {
        return db.queryAll();
    }

    public User save(User entity) {
        return db.persist(entity);
    }

    public void delete(String id) {
        db.remove(id);
    }

    private User validate(User user) {
        return user;
    }
}
