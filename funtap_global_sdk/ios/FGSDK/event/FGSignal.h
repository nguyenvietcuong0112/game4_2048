//
//  FGSignal.h — mirror KA/event/Signal.kt: multicast delegate ~ C# `event Action`.
//  Copy-on-invoke (≈ CopyOnWriteArrayList); nuốt + log exception từng handler để không chặn handler khác.
//  Facade command / Func (có return) dùng std::function nullable trực tiếp, KHÔNG dùng Signal (như Kotlin).
//
#pragma once
#import <Foundation/Foundation.h>
#include <functional>
#include <mutex>
#include <vector>

#if !defined(__OBJC__)
#error "FGSignal.h là ObjC++ — chỉ include từ file .mm"
#endif

template <typename... Args>
class FGSignalBase {
public:
    using Fn = std::function<void(Args...)>;

    // Kotlin `+=` — trả token để remove (C++ không so sánh được std::function)
    int add(Fn h) {
        std::lock_guard<std::mutex> l(_m);
        _handlers.push_back({++_seq, std::move(h)});
        return _seq;
    }

    // Kotlin `-=`
    void remove(int token) {
        std::lock_guard<std::mutex> l(_m);
        for (auto it = _handlers.begin(); it != _handlers.end(); ++it) {
            if (it->id == token) { _handlers.erase(it); break; }
        }
    }

    void invoke(Args... args) {
        std::vector<Entry> copy;
        {
            std::lock_guard<std::mutex> l(_m);
            copy = _handlers;
        }
        for (auto &e : copy) {
            @try {
                try { e.fn(args...); }
                catch (const std::exception &ce) { NSLog(@"[FGSignal] handler fail: %s", ce.what()); }
            } @catch (id ex) {
                NSLog(@"[FGSignal] handler fail: %@", ex);
            }
        }
    }

    void clear() {
        std::lock_guard<std::mutex> l(_m);
        _handlers.clear();
    }

private:
    struct Entry { int id; Fn fn; };
    std::vector<Entry> _handlers;
    std::mutex _m;
    int _seq = 0;
};

using FGSignal = FGSignalBase<>;
template <typename A> using FGSignal1 = FGSignalBase<A>;
template <typename A, typename B> using FGSignal2 = FGSignalBase<A, B>;
