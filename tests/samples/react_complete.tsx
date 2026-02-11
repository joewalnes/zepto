/**
 * Complete React TSX example demonstrating various syntax elements
 */

import React, {
    useState,
    useEffect,
    useCallback,
    useMemo,
    useRef,
    useContext,
    createContext,
    forwardRef,
    memo,
    lazy,
    Suspense,
} from 'react';
import type { FC, ReactNode, MouseEvent, ChangeEvent, FormEvent } from 'react';

// Types and interfaces
interface User {
    id: string;
    name: string;
    email: string;
}

interface Props {
    title: string;
    children?: ReactNode;
    onClick?: () => void;
}

type ButtonVariant = 'primary' | 'secondary' | 'danger';

// Context
interface ThemeContextType {
    theme: 'light' | 'dark';
    toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextType | null>(null);

// Custom hook
function useTheme(): ThemeContextType {
    const context = useContext(ThemeContext);
    if (!context) {
        throw new Error('useTheme must be used within ThemeProvider');
    }
    return context;
}

// Functional component with props
const Button: FC<{
    variant?: ButtonVariant;
    disabled?: boolean;
    onClick?: (e: MouseEvent<HTMLButtonElement>) => void;
    children: ReactNode;
}> = ({ variant = 'primary', disabled, onClick, children }) => {
    const className = `btn btn-${variant}`;

    return (
        <button
            className={className}
            disabled={disabled}
            onClick={onClick}
            type="button"
        >
            {children}
        </button>
    );
};

// Component with useState and useEffect
function Counter({ initial = 0 }: { initial?: number }) {
    const [count, setCount] = useState<number>(initial);
    const [isEven, setIsEven] = useState<boolean>(initial % 2 === 0);

    useEffect(() => {
        setIsEven(count % 2 === 0);
    }, [count]);

    useEffect(() => {
        console.log('Counter mounted');
        return () => {
            console.log('Counter unmounted');
        };
    }, []);

    const increment = useCallback(() => {
        setCount((prev) => prev + 1);
    }, []);

    const decrement = useCallback(() => {
        setCount((prev) => prev - 1);
    }, []);

    return (
        <div className="counter">
            <span>Count: {count}</span>
            <span>{isEven ? 'Even' : 'Odd'}</span>
            <Button onClick={decrement}>-</Button>
            <Button onClick={increment}>+</Button>
        </div>
    );
}

// Component with useRef
function InputWithFocus() {
    const inputRef = useRef<HTMLInputElement>(null);

    const focusInput = () => {
        inputRef.current?.focus();
    };

    return (
        <>
            <input ref={inputRef} type="text" placeholder="Type here..." />
            <Button onClick={focusInput}>Focus Input</Button>
        </>
    );
}

// Component with useMemo
function ExpensiveList({ items }: { items: string[] }) {
    const sortedItems = useMemo(() => {
        console.log('Sorting items...');
        return [...items].sort();
    }, [items]);

    return (
        <ul>
            {sortedItems.map((item, index) => (
                <li key={index}>{item}</li>
            ))}
        </ul>
    );
}

// forwardRef component
const FancyInput = forwardRef<HTMLInputElement, { label: string }>(
    ({ label }, ref) => (
        <label>
            {label}
            <input ref={ref} type="text" />
        </label>
    )
);

FancyInput.displayName = 'FancyInput';

// memo component
const UserCard = memo<{ user: User }>(({ user }) => (
    <div className="user-card">
        <h3>{user.name}</h3>
        <p>{user.email}</p>
    </div>
));

UserCard.displayName = 'UserCard';

// Lazy loaded component
const LazyComponent = lazy(() => import('./HeavyComponent'));

// Form component with controlled inputs
function ContactForm() {
    const [formData, setFormData] = useState({
        name: '',
        email: '',
        message: '',
    });
    const [errors, setErrors] = useState<Record<string, string>>({});
    const [isSubmitting, setIsSubmitting] = useState(false);

    const handleChange = (
        e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>
    ) => {
        const { name, value } = e.target;
        setFormData((prev) => ({ ...prev, [name]: value }));
    };

    const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        setIsSubmitting(true);

        try {
            // Simulate API call
            await new Promise((resolve) => setTimeout(resolve, 1000));
            console.log('Form submitted:', formData);
        } catch (error) {
            setErrors({ submit: 'Failed to submit form' });
        } finally {
            setIsSubmitting(false);
        }
    };

    return (
        <form onSubmit={handleSubmit}>
            <div>
                <label htmlFor="name">Name:</label>
                <input
                    id="name"
                    name="name"
                    type="text"
                    value={formData.name}
                    onChange={handleChange}
                    required
                />
            </div>

            <div>
                <label htmlFor="email">Email:</label>
                <input
                    id="email"
                    name="email"
                    type="email"
                    value={formData.email}
                    onChange={handleChange}
                    required
                />
            </div>

            <div>
                <label htmlFor="message">Message:</label>
                <textarea
                    id="message"
                    name="message"
                    value={formData.message}
                    onChange={handleChange}
                    rows={4}
                />
            </div>

            {errors.submit && <p className="error">{errors.submit}</p>}

            <Button variant="primary" disabled={isSubmitting}>
                {isSubmitting ? 'Submitting...' : 'Submit'}
            </Button>
        </form>
    );
}

// Conditional rendering examples
function ConditionalExamples({ show, items }: { show: boolean; items: string[] }) {
    return (
        <>
            {/* Boolean condition */}
            {show && <div>Visible when show is true</div>}

            {/* Ternary operator */}
            {show ? <span>Yes</span> : <span>No</span>}

            {/* Null check */}
            {items?.length > 0 && (
                <ul>
                    {items.map((item) => (
                        <li key={item}>{item}</li>
                    ))}
                </ul>
            )}

            {/* Empty state */}
            {items.length === 0 ? (
                <p>No items found</p>
            ) : (
                <p>{items.length} items</p>
            )}
        </>
    );
}

// Component with inline styles
function StyledBox() {
    const style: React.CSSProperties = {
        backgroundColor: '#f0f0f0',
        padding: '20px',
        borderRadius: '8px',
        boxShadow: '0 2px 4px rgba(0, 0, 0, 0.1)',
    };

    return (
        <div style={style}>
            <p style={{ color: 'blue', fontWeight: 'bold' }}>
                Styled content
            </p>
        </div>
    );
}

// Event handling examples
function EventExamples() {
    const handleClick = (e: MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        console.log('Button clicked');
    };

    const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
        if (e.key === 'Enter') {
            console.log('Enter pressed');
        }
    };

    return (
        <div>
            <button onClick={handleClick}>Click me</button>
            <button onClick={() => console.log('Inline handler')}>
                Inline
            </button>
            <input onKeyDown={handleKeyDown} />
        </div>
    );
}

// Main App component
export default function App() {
    const [theme, setTheme] = useState<'light' | 'dark'>('light');

    const toggleTheme = useCallback(() => {
        setTheme((prev) => (prev === 'light' ? 'dark' : 'light'));
    }, []);

    const themeValue = useMemo(
        () => ({ theme, toggleTheme }),
        [theme, toggleTheme]
    );

    return (
        <ThemeContext.Provider value={themeValue}>
            <div className={`app theme-${theme}`}>
                <header>
                    <h1>React TSX Example</h1>
                    <Button onClick={toggleTheme}>
                        Toggle Theme ({theme})
                    </Button>
                </header>

                <main>
                    <section>
                        <h2>Counter</h2>
                        <Counter initial={10} />
                    </section>

                    <section>
                        <h2>Form</h2>
                        <ContactForm />
                    </section>

                    <section>
                        <h2>Lazy Component</h2>
                        <Suspense fallback={<div>Loading...</div>}>
                            <LazyComponent />
                        </Suspense>
                    </section>
                </main>

                <footer>
                    <p>&copy; 2024 Example App</p>
                </footer>
            </div>
        </ThemeContext.Provider>
    );
}

// Named exports
export { Button, Counter, ThemeContext, useTheme };
export type { Props, User, ButtonVariant };
