import React from 'react';
import { createRoot } from 'react-dom/client';

function App() {
  return <main><h1>Hello World from React</h1></main>;
}

createRoot(document.getElementById('root')).render(<App />);